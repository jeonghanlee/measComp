#include <stdio.h>

#include "mcBoard_E-TC32.h"


mcE_TC32::mcE_TC32(const char *address)
  : mcBoard(address)
{
    strcpy(boardName_, "TC-32"); // new firmware had the TC-32 as the product name
    biBoardType_    = ETC32_PID;
    biNumADCChans_  = 0;
    biADCRes_       = 0;
    biNumDACChans_  = 0;
    biDACRes_       = 0;
    biNumTempChans_ = 32;
    biDInNumDevs_   = 1;
    diDevType_      = AUXPORT;
    diInMask_       = 0;
    diOutMask_      = 0;
    diNumBits_      = 32;

    // Open Ethernet socket
    deviceInfo_.device.connectCode = 0x0;   // default connect code
    deviceInfo_.device.frameID = 0;         // zero out the frameID
    deviceInfo_.device.Address.sin_family = AF_INET;
    deviceInfo_.device.Address.sin_port = htons(COMMAND_PORT);
    deviceInfo_.device.Address.sin_addr.s_addr = INADDR_ANY;
    if (inet_aton(address_, &deviceInfo_.device.Address.sin_addr) == 0) {
        printf("Improper destination address.\n");
        return;
    }

    if ((deviceInfo_.device.sock = openDevice(inet_addr(inet_ntoa(deviceInfo_.device.Address.sin_addr)),
                                              deviceInfo_.device.connectCode)) < 0) {
        printf("Error opening socket\n");
        return;
    }

    deviceInfo_.units = CELSIUS;
    deviceInfo_.wait = 0x0;
    for (int i = 0; i< 64; i++) {
        deviceInfo_.config_values[i] = CHAN_DISABLE;   // disable all channels
    }
}

// add the new constructor to pass the name into the class object
mcE_TC32::mcE_TC32(const char *address, const char* boardName)
  : mcBoard(address)
{
    strcpy(boardName_, boardName);
    biBoardType_    = ETC32_PID;
    biNumADCChans_  = 0;
    biADCRes_       = 0;
    biNumDACChans_  = 0;
    biDACRes_       = 0;
    biNumTempChans_ = 32;
    biDInNumDevs_   = 1;
    diDevType_      = AUXPORT;
    diInMask_       = 0;
    diOutMask_      = 0;
    diNumBits_      = 8; // The main issue is here, if we increase this number more than 16, no seg fault, however, we don't need the DIN, so diable the completerly in Poller...
    // Somehow the old driver doesn't work with the latest firmware at all, because it doesn't have DI OUT (32)
    // The correcto device type should be FIRSTPORTA and FIRSTPORTB if we don't use TC-32-exp.
    // https://github.com/mccdaq/uldaq/blob/24ba881e81ceeb24ff924852c7f56dda072d0282/src/net/dio/DioETc32.cpp#L11
    // It looks like we have to develop the only TC-32 (Ethernet model( based on uldaq instead of the cbw_linuxSrc....
    // 2021.05.30 Jeong Han Lee
    // https://www.mccdaq.com/PDFs/Manuals/UL-Linux/c/tc32.html
    deviceInfo_.device.connectCode = 0x0;   // default connect code
    deviceInfo_.device.frameID = 0;         // zero out the frameID
    deviceInfo_.device.Address.sin_family = AF_INET;
    deviceInfo_.device.Address.sin_port = htons(COMMAND_PORT);
    deviceInfo_.device.Address.sin_addr.s_addr = INADDR_ANY;
    if (inet_aton(address_, &deviceInfo_.device.Address.sin_addr) == 0) {
        printf("Improper destination address.\n");
        return;
    }
    if ((deviceInfo_.device.sock = openDevice(inet_addr(inet_ntoa(deviceInfo_.device.Address.sin_addr)),
                                              deviceInfo_.device.connectCode)) < 0) {
        printf("Error opening socket\n");
        return;
    }

    deviceInfo_.units = CELSIUS;
    deviceInfo_.wait = 0x0;
    for (int i = 0; i< 64; i++) {
        deviceInfo_.config_values[i] = CHAN_DISABLE;   // disable all channels
    }
}

int mcE_TC32::cbSetConfig(int InfoType, int DevNum, int ConfigItem, int ConfigVal) {
    switch (InfoType) {
    case BOARDINFO:
        switch (ConfigItem) {
        case BICHANTCTYPE:
            deviceInfo_.config_values[DevNum] = ConfigVal;
            TinConfigW_E_TC32(&deviceInfo_);
            break;

        default:
            printf("mcBoardE_TC32::setConfig error unknown ConfigItem %d\n", ConfigItem);
            return BADCONFIGITEM;
            break;
    }
    break;

    default:
        printf("mcBoardE_TC32::setConfig error unknown InfoType %d\n", InfoType);
        return BADCONFIGTYPE;
    break;
    }
    return NOERRORS;
}

int mcE_TC32::cbDBitOut(int PortType, int BitNum, USHORT BitValue)
{
    uint32_t value;
    uint32_t mask = 0x1 << BitNum;
    // Read the current output register
    if (!DOutR_E_TC32(&deviceInfo_, &value)) {
        return BADBOARD;
    }
    // Set or clear the bit
    if (BitValue) {
        value |= mask;
    } else {
        value &= ~mask;
    }
    if (!DOutW_E_TC32(&deviceInfo_, BASE, value)) {
        return BADBOARD;
    }
    return NOERRORS;
}

int mcE_TC32::cbDIn(int PortType, USHORT *DataValue)
{
    uint8_t value;
    if (!DIn_E_TC32(&deviceInfo_, &value)) {
        return BADBOARD;
    }
    *DataValue = value;
    return NOERRORS;
}

int mcE_TC32::cbTIn(int Chan, int Scale, float *TempValue, int Options)
{
    uint8_t channel = Chan;
    uint8_t units;
    switch (Scale) {
    case VOLTS:
        units = VOLTAGE;
        break;
    case NOSCALE:
        units = ADC_CODE;
        break;
    default:
        units = CELSIUS;
        break;
    }
    if (!Tin_E_TC32(&deviceInfo_, channel, units, 0, TempValue)) {
        return BADBOARD;
    }
    switch (Scale) {
    case KELVIN:
        *TempValue += 273.15;
        break;
    case FAHRENHEIT:
        *TempValue = (*TempValue * 1.8) + 32;
        break;
    default:
        break;
    }
    return NOERRORS;
}
