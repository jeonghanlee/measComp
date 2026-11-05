#include <cstdio>
#include <cstring>
#include <cmath>
#include <asynDriver.h>
#include <asynInt32.h>
#include <asynInt32SyncIO.h>
#include <asynShellCommands.h>
#include <dbAccess.h>
#include <dbStaticLib.h>
#include <epicsExit.h>
#include <iocInit.h>

extern "C" int review_registerRecordDeviceDriver(DBBASE *);
extern "C" int MultiFunctionConfig(const char *, const char *, int, int);

static double field(const char *name)
{
    DBADDR address;
    double value = -1000000;
    if (dbNameToAddr(name, &address) != 0) return value;
    if (dbGetField(&address, DBR_DOUBLE, &value, 0, 0, 0) != 0) return -1000000;
    return value;
}

static void state(asynUser *port)
{
    int connected = -1, automatic = -1, enabled = -1;
    pasynManager->isConnected(port, &connected);
    pasynManager->isAutoConnect(port, &automatic);
    pasynManager->isEnabled(port, &enabled);
    double value = field("TEST:T0.VAL");
    std::printf("STATE %d %d %d %.0f %.0f %.0f %.9g %.0f %.9g\n", connected, automatic, enabled,
                field("TEST:T0.PACT"), field("TEST:T0.UDF"), field("TEST:T0.SEVR"), value,
                field("TEST:T31.SEVR"), field("TEST:T31.VAL"));
}

static int writeSetting(const char *parameter, int value, int address = 0)
{
    asynUser *user = 0;
    asynStatus status = pasynInt32SyncIO->connect("DAQ", address, &user, parameter);
    if (status == asynSuccess) status = pasynInt32SyncIO->write(user, value, 2.0);
    if (user) pasynInt32SyncIO->disconnect(user);
    return status;
}

static void readTC(int address, bool cached)
{
    asynUser *user = 0;
    epicsInt32 value = -1;
    asynStatus status = pasynInt32SyncIO->connect("DAQ", address, &user, "THERMOCOUPLE_TYPE");
    if (status == asynSuccess) {
        if (cached) {
            // Inspect the real cache while the disconnected port rejects queued I/O.
            asynInterface *interface = pasynManager->findInterface(user, asynInt32Type, 1);
            status = interface ? pasynManager->lockPort(user) : asynError;
            if (status == asynSuccess) {
                asynInt32 *int32 = static_cast<asynInt32 *>(interface->pinterface);
                status = int32->read(interface->drvPvt, user, &value);
                asynStatus unlocked = pasynManager->unlockPort(user);
                if (unlocked != asynSuccess) status = unlocked;
            }
        } else {
            status = pasynInt32SyncIO->read(user, &value, 2.0);
        }
    }
    if (user) pasynInt32SyncIO->disconnect(user);
    std::printf("TCREAD %d %d\n", status, value);
}

int main(int argc, char **argv)
{
    std::setvbuf(stdout, 0, _IONBF, 0);
    if (argc != 4) return 2;
    if (dbLoadDatabase(argv[1], 0, 0)) return 3;
    if (review_registerRecordDeviceDriver(pdbbase)) return 4;
    if (MultiFunctionConfig("DAQ", argv[3], 1, 1)) return 5;
    if (dbLoadRecords(argv[2], "P=TEST:,R=T0,PORT=DAQ,ADDR=0,SCAN=I/O Intr,PREC=3")) return 6;
    if (dbLoadRecords(argv[2], "P=TEST:,R=T31,PORT=DAQ,ADDR=31,SCAN=I/O Intr,PREC=3")) return 6;
    if (iocInit()) return 7;
    asynUser *port = pasynManager->createAsynUser(0, 0);
    if (pasynManager->connectDevice(port, "DAQ", -1) != asynSuccess) return 8;
    std::puts("READY");
    char command[80];
    while (std::fgets(command, sizeof(command), stdin)) {
        int value;
        if (!std::strncmp(command, "STATE", 5)) state(port);
        else if (std::sscanf(command, "AUTO %d", &value) == 1)
            std::printf("RESULT %d\n", asynAutoConnect("DAQ", -1, value));
        else if (std::sscanf(command, "ENABLE %d", &value) == 1)
            std::printf("RESULT %d\n", asynEnable("DAQ", -1, value));
        else if (std::sscanf(command, "READTC %d", &value) == 1)
            readTC(value, false);
        else if (std::sscanf(command, "CACHETC %d", &value) == 1)
            readTC(value, true);
        else if (std::sscanf(command, "TC31 %d", &value) == 1)
            std::printf("RESULT %d\n", writeSetting("THERMOCOUPLE_TYPE", value, 31));
        else if (std::sscanf(command, "TC %d", &value) == 1)
            std::printf("RESULT %d\n", writeSetting("THERMOCOUPLE_TYPE", value));
        else if (std::sscanf(command, "OTD31 %d", &value) == 1)
            std::printf("RESULT %d\n", writeSetting("THERMOCOUPLE_OPEN_DETECT", value, 31));
        else if (std::sscanf(command, "OTD %d", &value) == 1)
            std::printf("RESULT %d\n", writeSetting("THERMOCOUPLE_OPEN_DETECT", value));
        else if (!std::strncmp(command, "QUIT", 4)) break;
        else std::puts("UNKNOWN");
    }
    epicsExit(0);
    return 0;
}
