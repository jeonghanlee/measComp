#include <stdio.h>
#include <string>
#include <string.h>
#include <stdlib.h>
#include <osiSock.h>
#ifdef _WIN32
  #include "cbw.h"
#else
  #include "uldaq.h"
#endif

#include <epicsExport.h>
#include <epicsGuard.h>
#include <epicsMutex.h>
#include <epicsStdio.h>
#include <epicsString.h>
#include <epicsTime.h>
#include <measCompDiscover.h>

#define MAX_DEVICES 100
// All current Measurement Computing devices (E-1608, E-TC, TC32) use this port for
// discovery.  But it is configurable so we allow the user to specify it.
#define DEFAULT_DISCOVERY_PORT 54211
// Minimum time in seconds between broadcast discovery attempts.  It is shorter than the driver's
// five-second reconnect delay: a retry starts before it waits for the vendor-call lock, so the
// refresh it triggers can start later than the retry itself, and an equal interval would skip every
// second refresh under lock contention.  Ports retrying at different phases still share one refresh
// per reconnect delay.
#define INVENTORY_REFRESH_INTERVAL 4.0

static DaqDeviceDescriptor measCompInventory[MAX_DEVICES];
// Discovery port of each inventory entry.  Entries from a broadcast discovery were reached on the
// default discovery port; entries from a direct query record the port that was requested.  Together
// with the IP address in the descriptor's reserved field it identifies a direct-discovery endpoint,
// so two devices at one IP address on different discovery ports stay distinct.
static int measCompInventoryPort[MAX_DEVICES];
static int measCompNumDevices = 0;
bool measCompInventoryInitialized = false;
static epicsMutex inventoryMutex;
// Monotonic time of the most recent broadcast discovery attempt, 0 before the first one.
static epicsUInt64 lastDiscoveryAttempt = 0;
// Vendor status of the most recent inventory refresh; a change is reported once, so a persistent
// failure appears once in the log and once more when the query succeeds again.
static int lastRefreshStatus = 0;

#ifndef WIN32
// Copies the IP address of an Ethernet device into the reserved field of its descriptor.
// The device must not belong to a connected port: for a known descriptor the vendor library
// returns the existing device object, and releasing it deletes that object.
static void measCompReadIpAddress(DaqDeviceDescriptor& descriptor)
{
  if (descriptor.devInterface != ETHERNET_IFC) return;
  DaqDeviceHandle devHandle = ulCreateDaqDevice(descriptor);
  unsigned int maxLen = sizeof(descriptor.reserved);
  ulDevGetConfigStr(devHandle, DEV_CFG_IP_ADDR_STR, 0, descriptor.reserved, &maxLen);
  ulReleaseDaqDevice(devHandle);
}
#endif

int measCompDiscoverDevices()
{
  epicsGuard<epicsMutex> guard(inventoryMutex);
  int numDevices = MAX_DEVICES;
  int status;

  if (measCompInventoryInitialized) return 0;
  lastDiscoveryAttempt = epicsMonotonicGet();
  #ifdef WIN32
    cbIgnoreInstaCal();
    status = cbGetDaqDeviceInventory(ANY_IFC, measCompInventory, &numDevices);
    if (status) return status;
    // Windows eliminates leading zeros on USB device serial numbers, Linux does not.
    // Add the leading zero if the string length is 7
    for (int i=0; i<numDevices; i++) {
        if (measCompInventory[i].InterfaceType == USB_IFC) {
            if (strlen(measCompInventory[i].UniqueID) == 7) {
                std::string tempString = "0" + std::string(measCompInventory[i].UniqueID);
                strcpy(measCompInventory[i].UniqueID, tempString.c_str());
            }
        }
    } 
  #else
    status = ulGetDaqDeviceInventory(ANY_IFC, measCompInventory, (unsigned int *)&numDevices);
    if (status) return status;
    // Copy the IP address to the reserved field for Ethernet devices.
    for (int i=0; i<numDevices; i++) {
        measCompReadIpAddress(measCompInventory[i]);
    }
  #endif
  if (status) {
    printf("Error calling cbGetDaqDeviceInventory=%d\n", status);
    return status;
  }
  for (int i=0; i<numDevices; i++) measCompInventoryPort[i] = DEFAULT_DISCOVERY_PORT;
  measCompNumDevices = numDevices;
  measCompInventoryInitialized = true;
  return 0;
}

void measCompShowDevices()
{
  epicsGuard<epicsMutex> guard(inventoryMutex);
  measCompDiscoverDevices();
  printf("measCompShowDevices, numDevices=%d\n", measCompNumDevices);
  #ifdef WIN32
    for (int i=0; i<measCompNumDevices; i++) {
      printf("Device %d\n", i);
      printf("    ProductName: %s\n",   measCompInventory[i].ProductName);
      printf("      ProductID: %d\n",   measCompInventory[i].ProductID);
      printf("  InterfaceType: %d\n",   measCompInventory[i].InterfaceType);
      printf("      DevString: %s\n",   measCompInventory[i].DevString);
      printf("       UniqueID: %s\n",   measCompInventory[i].UniqueID);
      printf("           NUID: %llu\n", measCompInventory[i].NUID);
      printf("       Reserved: %s\n",   measCompInventory[i].Reserved);
    }
  #else
    for (int i=0; i<measCompNumDevices; i++) {
      printf("Device %d\n", i);
      printf("    ProductName: %s\n",   measCompInventory[i].productName);
      printf("      ProductID: %d\n",   measCompInventory[i].productId);
      printf("  InterfaceType: %d\n",   measCompInventory[i].devInterface);
      printf("      DevString: %s\n",   measCompInventory[i].devString);
      printf("       UniqueID: %s\n",   measCompInventory[i].uniqueId);
      printf("       Reserved: %s\n",   measCompInventory[i].reserved);
    }
  #endif
}

// Returns the inventory index of the device with this unique ID, or -1 if it is not in the inventory.
// Unique IDs are hexadecimal USB serial numbers or MAC addresses, which the vendor library reports
// in upper case, so the comparison ignores case.
static int measCompFindDevice(const char *uniqueId)
{
  for (int i=0; i<measCompNumDevices; i++) {
    #ifdef WIN32
      if (epicsStrCaseCmp(uniqueId, measCompInventory[i].UniqueID) == 0) return i;
    #else
      if (epicsStrCaseCmp(uniqueId, measCompInventory[i].uniqueId) == 0) return i;
    #endif
  }
  return -1;
}

// Queries Ethernet devices with a new broadcast and appends those whose unique ID is not yet in the
// inventory.  Known entries, their order and their vendor device objects are never touched, so the
// handles of connected ports stay valid.  Returns at once when less than INVENTORY_REFRESH_INTERVAL
// has passed since the last discovery attempt.  Returns the number of appended entries.
static int measCompRefreshInventory()
{
  epicsUInt64 now = epicsMonotonicGet();
  DaqDeviceDescriptor found[MAX_DEVICES];
  int added = 0;
  int status;
  #ifdef WIN32
    int numFound = MAX_DEVICES;
  #else
    unsigned int numFound = MAX_DEVICES;
  #endif

  if (lastDiscoveryAttempt &&
      (now - lastDiscoveryAttempt)/1.e9 < INVENTORY_REFRESH_INTERVAL) return 0;
  lastDiscoveryAttempt = now;
  #ifdef WIN32
    cbIgnoreInstaCal();
    status = cbGetDaqDeviceInventory(ETHERNET_IFC, found, &numFound);
  #else
    status = ulGetDaqDeviceInventory(ETHERNET_IFC, found, &numFound);
  #endif
  if (status != lastRefreshStatus) {
    if (status) printf("measCompRefreshInventory: inventory query failed, status=%d\n", status);
    else printf("measCompRefreshInventory: inventory query succeeded again\n");
    lastRefreshStatus = status;
  }
  if (status) return 0;
  for (int i=0; i<(int)numFound; i++) {
    #ifdef WIN32
      if (measCompFindDevice(found[i].UniqueID) != -1) continue;
    #else
      if (measCompFindDevice(found[i].uniqueId) != -1) continue;
    #endif
    if (measCompNumDevices >= MAX_DEVICES) {
      printf("Device inventory is full\n");
      break;
    }
    #ifndef WIN32
      measCompReadIpAddress(found[i]);
    #endif
    measCompInventoryPort[measCompNumDevices] = DEFAULT_DISCOVERY_PORT;
    measCompInventory[measCompNumDevices++] = found[i];
    added++;
  }
  return added;
}

/** Create a measComp device.
  * This method finds a device and connects to it.  It is called from the driver constructor.
  * \param[in] uniqueID 
  *                     This is an 8 digital hex serial number for USB devices without a leading 0x.
  *                     For Ethernet devices it can be:
  *                         An IP DNS name with optional discovery port, e.g. gse-e1608-6:54211
  *                         An IP address with optional discovery port, e.g. 10.54.160.63:54211
  *                         A MAC address, e.g. 00:80:2F:24:53:E5
  * \param[out] deviceDescriptor Pointer to a DaqDeviceDescription structure for this device
  * \param[out] handle A handle for this device.  
  *                         On Windows this is the index in the device inventory list.
  *                         On Linux it is a DaqDeviceHandle.
  */
int measCompCreateDevice(std::string uniqueId, DaqDeviceDescriptor& deviceDescriptor, long long *handle)
{
  epicsGuard<epicsMutex> guard(inventoryMutex);
  size_t colon;
  std::string host = uniqueId;
  std::string port;
  struct sockaddr_in ipAddr;
  bool isEthernet = false;
  char *endptr;
  int portNum = DEFAULT_DISCOVERY_PORT;
  int status;
  int devIndex=-1;
  char ipAddrAsString[25];
  double timeout = 1.0;

  *handle = 0;
  status = measCompDiscoverDevices();
  if (status) return status;
  // If the uniqueId is a hex number it is USB, else Ethernet
  strtol(uniqueId.c_str(), &endptr, 16);
  if (*endptr != '\0') isEthernet = true;

  // Use hostToIPAddr for 2 reasons:
  // - It will translate IP names to IP addresses
  // - It will fail if the uniqueId is a MAC address
  status = aToIPAddr(uniqueId.c_str(), portNum, &ipAddr);
  if (isEthernet && (status == 0)) {
    ipAddrToDottedIP(&ipAddr, ipAddrAsString, sizeof(ipAddrAsString));
    // The string from ipAddrToDottedIP will always have a :port at the end
    // Parse the port and remove from the host string.
    host = ipAddrAsString;
    colon = host.find(":");
    if (colon != std::string::npos) {
      port = host.substr(colon+1, std::string::npos);
      portNum = atoi(port.c_str());
      host = host.substr(0, colon);
    }
    // See if this endpoint is already known: the same IP address on the same discovery port.  The
    // port is part of the identity because distinct devices can share an IP address and differ only
    // in their discovery port.
    for (int i=0; i<measCompNumDevices; i++) {
      #ifdef WIN32
        /*  This logic does not work on Windows because there is no way to retrieve the IP address and copy it to .Reserved
         *  This is OK, it is just slightly less efficient because it will always call cbGetNetDeviceDescriptor unless UniqueID is a MAC address.
        if (host.compare(measCompInventory[i].Reserved) == 0 && portNum == measCompInventoryPort[i]) {
          devIndex = i;
          break;
        } */
      #else
        if (host.compare(measCompInventory[i].reserved) == 0 && portNum == measCompInventoryPort[i]) {
          devIndex = i;
          break;
        }
      #endif
    }
    // We did not find this device on the local subnet, create a new one
    if (devIndex == -1) {
      if (measCompNumDevices >= MAX_DEVICES) {
        printf("Device inventory is full\n");
        return -1;
      }
      DaqDeviceDescriptor descriptor = {};
      #ifdef WIN32
        status = cbGetNetDeviceDescriptor((char*)host.c_str(), portNum,
                                          &descriptor, (int) (timeout * 1000));
      #else
        status = ulGetNetDaqDeviceDescriptor((char*)host.c_str(), portNum, NULL,
                                             &descriptor, timeout);
      #endif
      if (status) {
          printf("Error calling cbGetNetDeviceDescriptor=%d\n", status);
          return -1;
      }
      #ifndef WIN32
        epicsSnprintf(descriptor.reserved, sizeof(descriptor.reserved), "%s", host.c_str());
      #endif
      // A device reached through another selector for the same unique ID keeps its single entry
      // and vendor object; otherwise the endpoint is appended with the port it was reached on.
      #ifdef WIN32
        devIndex = measCompFindDevice(descriptor.UniqueID);
      #else
        devIndex = measCompFindDevice(descriptor.uniqueId);
      #endif
      if (devIndex == -1) {
        devIndex = measCompNumDevices++;
        measCompInventoryPort[devIndex] = portNum;
        measCompInventory[devIndex] = descriptor;
      }
    }
  }
  else {
    // uniqueId was not an IP address or IP DNS name, so it must be a serial number (USB) or MAC address (Ethernet)
    // Search the inventory for the matching UniqueID.  A MAC address that is not in the inventory
    // triggers one bounded refresh, because the device may have become available after the
    // previous discovery.
    devIndex = measCompFindDevice(uniqueId.c_str());
    if (devIndex == -1 && isEthernet && measCompRefreshInventory() > 0) {
      devIndex = measCompFindDevice(uniqueId.c_str());
    }
  }
  if (devIndex != -1) {
    #ifdef WIN32
      status = cbCreateDaqDevice(devIndex, measCompInventory[devIndex]);
      if (status) {
        printf("Error calling cbCreateDaqDevice=%d\n", status);
        return -1;
      }
      *handle = devIndex;
    #else
      DaqDeviceHandle devHandle = ulCreateDaqDevice(measCompInventory[devIndex]);
      if (!devHandle) {
        printf("Error calling ulCreateDaqDevice devIndex=%d\n", devIndex);
        return -1;
      }
      UlError error = ulConnectDaqDevice(devHandle);
      if (error) {
        printf("Error calling ulConnectDaqDevice error=%d\n", error);
        ulReleaseDaqDevice(devHandle);
        return -1;
      }
      *handle = devHandle;
    #endif
    //
    deviceDescriptor = measCompInventory[devIndex];
    return 0;
  }
  return -1;
}

