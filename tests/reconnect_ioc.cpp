#include <cstdio>
#include <cstring>
#include <cmath>
#include <cstdlib>
#include <string>
#include <asynDriver.h>
#include <asynInt32.h>
#include <asynInt32SyncIO.h>
#include <asynFloat64SyncIO.h>
#include <asynOctetSyncIO.h>
#include <asynUInt32Digital.h>
#include <asynUInt32DigitalSyncIO.h>
#include <asynEnumSyncIO.h>
#include <asynShellCommands.h>
#include <dbAccess.h>
#include <dbStaticLib.h>
#include <dbScan.h>
#include <epicsExit.h>
#include <iocInit.h>
#include <initHooks.h>
#include <measCompDiscover.h>

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
    std::printf("STATE %d %d %d %.0f %.0f %.0f %.9g %.0f %.9g %.0f %.0f\n", connected, automatic, enabled,
                field("TEST:T0.PACT"), field("TEST:T0.UDF"), field("TEST:T0.SEVR"), value,
                field("TEST:T31.SEVR"), field("TEST:T31.VAL"),
                field("TEST:D0.SEVR"), field("TEST:D0.VAL"));
}

static void stateB(asynUser *port)
{
    int connected = -1;
    pasynManager->isConnected(port, &connected);
    std::printf("STATEB %d %.0f %.0f %.0f %.9g\n", connected, field("TEST:B0.PACT"),
                field("TEST:B0.UDF"), field("TEST:B0.SEVR"), field("TEST:B0.VAL"));
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

static int writeDigital(const char *parameter, unsigned int value, unsigned int mask)
{
    return pasynUInt32DigitalSyncIO->writeOnce("DAQ", 1, value, mask, 2.0, parameter);
}

static int loadEnums(const char *inputTemplate, const char *model)
{
    std::string directory(inputTemplate);
    directory = directory.substr(0, directory.find_last_of('/') + 1);
    int last = !std::strcmp(model, "e1608") ? 7 : 31;
    for (int addr=0; addr<=last; addr+=last) {
        char macros[256];
        std::snprintf(macros, sizeof(macros),
            "P=TEST:,R=A%d,PORT=DAQ,ADDR=%d,SCAN=Passive,EGUF=10,EGUL=-10,HOPR=10,LOPR=-10,PREC=3,RANGE=0",
            addr, addr);
        if (dbLoadRecords(inputTemplate, macros)) return 6;
        if (!std::strcmp(model, "e1608")) {
            std::snprintf(macros, sizeof(macros),
                "P=TEST:,R=V%d,PORT=DAQ,ADDR=%d,SCAN=Passive,HOPR=10,LOPR=-10,PREC=3,RANGE=0", addr, addr);
            if (dbLoadRecords((directory + "measCompVoltageIn.template").c_str(), macros)) return 6;
        }
    }
    if (!std::strcmp(model, "e1608")) {
        for (int addr=0; addr<2; addr++) {
            char macros[256];
            std::snprintf(macros, sizeof(macros),
                "P=TEST:,R=O%d,PORT=DAQ,ADDR=%d,PINI=NO,EGUF=10,EGUL=-10,HOPR=10,LOPR=-10,DRVH=10,DRVL=-10,PREC=3,VAL=0",
                addr, addr);
            if (dbLoadRecords((directory + "measCompAnalogOut.template").c_str(), macros)) return 6;
        }
    }
    return 0;
}

static int loadBounds(const char *inputTemplate, const char *model)
{
    bool metadata = !std::strcmp(model, "tc32");
    const char *scans[] = {".1 second", metadata ? "Passive" : "I/O Intr", "Passive"};
    for (int addr=0; addr<3; addr++) {
        char macros[256];
        std::snprintf(macros, sizeof(macros),
            "P=TEST:,R=A%d,PORT=DAQ,ADDR=%d,SCAN=%s,EGUF=%d,EGUL=%d,HOPR=10,LOPR=-10,PREC=6,RANGE=0",
            addr, addr, scans[addr], metadata ? 1 : 10, metadata ? 0 : -10);
        if (dbLoadRecords(inputTemplate, macros)) return 6;
    }
    return 0;
}

static void putNumber(const char *name, double value)
{
    DBADDR address;
    long status = dbNameToAddr(name, &address);
    double actual = -1000000;
    if (!status) {
        status = dbPutField(&address, DBR_DOUBLE, &value, 1);
        dbScanLock(address.precord);
        actual = field(name);
        dbScanUnlock(address.precord);
    }
    std::printf("RESULT %ld %.17g\n", status, actual);
}

// Prints the value, severity, undefined state, timestamp and TSE field of a record, the timestamp as
// seconds and nanoseconds since the EPICS epoch.
static void readRecord(const char *record)
{
    DBADDR address;
    if (dbNameToAddr(record, &address)) {
        std::puts("RECORDERROR record missing");
        return;
    }
    std::string name(record);
    dbScanLock(address.precord);
    double value = field((name + ".VAL").c_str());
    double severity = field((name + ".SEVR").c_str());
    double undefined = field((name + ".UDF").c_str());
    double eventSource = field((name + ".TSE").c_str());
    double seconds = address.precord->time.secPastEpoch;
    double nanoseconds = address.precord->time.nsec;
    dbScanUnlock(address.precord);
    std::printf("RECORD %.9g %.0f %.0f %.0f %.0f %.0f\n", value, severity, undefined, seconds, nanoseconds,
                eventSource);
}

// Prints the driver's LAST_ERROR_MESSAGE parameter, read through the public asynOctet interface.
static void readMessage()
{
    asynUser *user = 0;
    char buffer[256] = "";
    size_t received = 0;
    int eomReason = 0;
    asynStatus status = pasynOctetSyncIO->connect("DAQ", 0, &user, "LAST_ERROR_MESSAGE");
    if (status == asynSuccess) {
        status = pasynOctetSyncIO->read(user, buffer, sizeof(buffer) - 1, 2.0, &received, &eomReason);
        buffer[received < sizeof(buffer) ? received : sizeof(buffer) - 1] = '\0';
        pasynOctetSyncIO->disconnect(user);
    }
    std::printf("MESSAGE %d %s\n", status, buffer);
}

// Prints the string value of a record by name.
static void readString(const char *record)
{
    DBADDR address;
    char buffer[MAX_STRING_SIZE + 1] = "";
    std::string name(record);
    name += ".VAL";
    if (dbNameToAddr(name.c_str(), &address)) {
        std::puts("STRINGERROR record missing");
        return;
    }
    dbScanLock(address.precord);
    long status = dbGetField(&address, DBR_STRING, buffer, 0, 0, 0);
    dbScanUnlock(address.precord);
    buffer[MAX_STRING_SIZE] = '\0';
    if (status) std::puts("STRINGERROR read failed");
    else std::printf("STRING %s\n", buffer);
}

// Prints the driver's cached value of an integer parameter, read through the public asynInt32 interface.
static void readSetting(const char *parameter, int address)
{
    epicsInt32 value = -1;
    asynStatus status = pasynInt32SyncIO->readOnce("DAQ", address, &value, 2.0, parameter);
    std::printf("SETTING %d %d\n", status, value);
}

static void readAnalog(int addr, const char *record)
{
    epicsInt32 low = 0, high = 0;
    asynStatus status = pasynInt32SyncIO->getBoundsOnce("DAQ", addr, &low, &high, "ANALOG_IN_VALUE");
    DBADDR address;
    if (dbNameToAddr(record, &address)) {
        std::puts("ANALOGERROR record missing");
        return;
    }
    const char *fields[] = {"RVAL", "VAL", "ESLO", "EOFF", "EGUL", "EGUF", "UDF", "SEVR", "PACT", "LINR"};
    double values[11];
    dbScanLock(address.precord);
    for (int i=0; i<10; i++)
        values[i] = field((std::string(record) + "." + fields[i]).c_str());
    values[10] = address.precord->time.secPastEpoch + address.precord->time.nsec * 1e-9;
    dbScanUnlock(address.precord);
    std::printf("ANALOG %d %d %d", status, low, high);
    for (int i=0; i<11; i++) std::printf(" %.17g", values[i]);
    std::puts("");
}

static void enumInitHook(initHookState state)
{
    if (state != initHookAfterInitDatabase) return;
    std::printf("ENUMINIT %d\n", interruptAccept);
    char command[16];
    if (!std::fgets(command, sizeof(command), stdin) || std::strcmp(command, "GO\n")) epicsExit(9);
    asynUser *port = pasynManager->createAsynUser(0, 0);
    int connected = -1;
    pasynManager->connectDevice(port, "DAQ", -1);
    pasynManager->isConnected(port, &connected);
    std::printf("ENUMCONNECTED %d %d\n", connected, interruptAccept);
    pasynManager->freeAsynUser(port);
}

static void enumEntry(const char *text, int value, int severity)
{
    std::printf(" |");
    for (const unsigned char *p=reinterpret_cast<const unsigned char *>(text); *p; p++)
        std::printf("%02x", *p);
    std::printf(",%d,%d", value, severity);
}

static void readEnums(int addr, const char *parameter, const char *record)
{
    const int states = 16;
    const char *prefixes[states] = {
        "ZR", "ON", "TW", "TH", "FR", "FV", "SX", "SV",
        "EI", "NI", "TE", "EL", "TV", "TT", "FT", "FF"
    };
    char *strings[states] = {};
    int values[states] = {}, severities[states] = {};
    size_t count = 0;
    asynStatus status = pasynEnumSyncIO->readOnce("DAQ", addr, strings, values,
        severities, states, &count, 2.0, parameter);
    DBADDR address;
    if (dbNameToAddr(record, &address)) {
        std::puts("ENUMERROR record missing");
        for (int i=0; i<states; i++) std::free(strings[i]);
        return;
    }
    char labels[states][MAX_STRING_SIZE] = {};
    int recordValues[states], recordSeverities[states];
    bool valid = true;
    dbScanLock(address.precord);
    for (int i=0; i<states; i++) {
        char name[100];
        DBADDR label;
        std::snprintf(name, sizeof(name), "%s.%sST", record, prefixes[i]);
        if (dbNameToAddr(name, &label) || dbGetField(&label, DBR_STRING, labels[i], 0, 0, 0)) valid = false;
        std::snprintf(name, sizeof(name), "%s.%sVL", record, prefixes[i]);
        recordValues[i] = static_cast<int>(field(name));
        std::snprintf(name, sizeof(name), "%s.%sSV", record, prefixes[i]);
        recordSeverities[i] = static_cast<int>(field(name));
        if (recordValues[i] == -1000000 || recordSeverities[i] == -1000000) valid = false;
    }
    dbScanUnlock(address.precord);
    std::printf("ENUM %d %zu %d", status, count, valid ? 0 : 1);
    for (size_t i=0; i<count; i++) enumEntry(strings[i], values[i], severities[i]);
    for (int i=0; i<states; i++) enumEntry(labels[i], recordValues[i], recordSeverities[i]);
    std::puts("");
    for (int i=0; i<states; i++) std::free(strings[i]);
}

static long writeEnumRecord(const char *record, int value)
{
    DBADDR address;
    epicsInt32 selected = value;
    long status = dbNameToAddr((std::string(record) + ".VAL").c_str(), &address);
    if (!status) status = dbPutField(&address, DBR_LONG, &selected, 1);
    return status;
}

static void enumValue(int addr, const char *parameter, const char *record)
{
    epicsInt32 value = -1;
    asynStatus status = pasynInt32SyncIO->readOnce("DAQ", addr, &value, 2.0, parameter);
    std::string name(record);
    std::printf("ENUMVALUE %d %d %.0f %.0f %.0f %.0f\n", status, value,
        field((name + ".RVAL").c_str()), field((name + ".PACT").c_str()),
        field((name + ".SEVR").c_str()), field((name + ".SDEF").c_str()));
}

int main(int argc, char **argv)
{
    std::setvbuf(stdout, 0, _IONBF, 0);
    if (argc != 5 && argc != 6 && argc != 7) return 2;
    bool enumMode = argc == 7;
    bool secondPort = argc == 6;
    if (dbLoadDatabase(argv[1], 0, 0)) return 3;
    if (review_registerRecordDeviceDriver(pdbbase)) return 4;
    if (MultiFunctionConfig("DAQ", argv[3], 1, 1)) return 5;
    if (secondPort && MultiFunctionConfig("DAQ2", argv[5], 1, 1)) return 5;
    if (enumMode) {
        if (!std::strncmp(argv[6], "bounds-", 7)) {
            if (loadBounds(argv[2], argv[5])) return 6;
        } else if (loadEnums(argv[2], argv[5])) return 6;
        if (!std::strcmp(argv[6], "init")) initHookRegister(enumInitHook);
    } else {
        if (dbLoadRecords(argv[2], "P=TEST:,R=T0,PORT=DAQ,ADDR=0,SCAN=I/O Intr,PREC=3,TSE=-2")) return 6;
        if (dbLoadRecords(argv[2], "P=TEST:,R=T1,PORT=DAQ,ADDR=1,SCAN=I/O Intr,PREC=3,TSE=-2")) return 6;
        if (dbLoadRecords(argv[2], "P=TEST:,R=T2,PORT=DAQ,ADDR=2,SCAN=I/O Intr,PREC=3")) return 6;
        if (dbLoadRecords(argv[2], "P=TEST:,R=T31,PORT=DAQ,ADDR=31,SCAN=I/O Intr,PREC=3,TSE=-2")) return 6;
        // The records of the network TC32 diagnostics: the cold-junction temperature of channels 0 and 31
        // and the settings and dates of bank 0, from the directory of the temperature template.
        std::string directory(argv[2]);
        directory = directory.substr(0, directory.find_last_of('/') + 1);
        std::string cjcTemplate = directory + "measCompTemperatureCJC.template";
        std::string bankTemplate = directory + "measCompTemperatureBank.template";
        if (dbLoadRecords(cjcTemplate.c_str(), "P=TEST:,R=T0,PORT=DAQ,ADDR=0,PREC=3")) return 6;
        if (dbLoadRecords(cjcTemplate.c_str(), "P=TEST:,R=T31,PORT=DAQ,ADDR=31,PREC=3")) return 6;
        if (dbLoadRecords(bankTemplate.c_str(), "P=TEST:,R=Bank0,PORT=DAQ,ADDR=0")) return 6;
        if (dbLoadRecords(argv[4], "P=TEST:,R=D0,PORT=DAQ,ADDR=0,MASK=1")) return 6;
        if (secondPort && dbLoadRecords(argv[2], "P=TEST:,R=B0,PORT=DAQ2,ADDR=0,SCAN=I/O Intr,PREC=3")) return 6;
    }
    if (iocInit()) return 7;
    asynUser *port = pasynManager->createAsynUser(0, 0);
    if (pasynManager->connectDevice(port, "DAQ", -1) != asynSuccess) return 8;
    asynUser *portB = 0;
    if (secondPort) {
        portB = pasynManager->createAsynUser(0, 0);
        if (pasynManager->connectDevice(portB, "DAQ2", -1) != asynSuccess) return 8;
    }
    std::puts("READY");
    char command[200];
    while (std::fgets(command, sizeof(command), stdin)) {
        int value;
        double number;
        unsigned int digital, mask;
        char parameter[64], record[64];
        if (!std::strncmp(command, "CONNECTED", 9)) {
            int connected = -1;
            pasynManager->isConnected(port, &connected);
            std::printf("CONNECTED %d\n", connected);
        }
        else if (std::sscanf(command, "ANALOG %d %63s", &value, record) == 2)
            readAnalog(value, record);
        else if (std::sscanf(command, "PUT %63s %lf", record, &number) == 2)
            putNumber(record, number);
        else if (std::sscanf(command, "ENUM %d %63s %63s", &value, parameter, record) == 3)
            readEnums(value, parameter, record);
        else if (std::sscanf(command, "WRITESET %63s %d", parameter, &value) == 2)
            std::printf("RESULT %d\n", writeSetting(parameter, value));
        else if (std::sscanf(command, "READSET %63s", parameter) == 1)
            readSetting(parameter, 0);
        else if (std::sscanf(command, "STRING %63s", record) == 1)
            readString(record);
        else if (std::sscanf(command, "ENUMSET %63s %d", record, &value) == 2)
            std::printf("RESULT %ld\n", writeEnumRecord(record, value));
        else if (std::sscanf(command, "ENUMVALUE %d %63s %63s", &value, parameter, record) == 3)
            enumValue(value, parameter, record);
        else if (!std::strncmp(command, "STATEB", 6)) {
            if (portB) stateB(portB);
            else std::puts("STATEB none");
        }
        else if (!std::strncmp(command, "SHOW", 4)) {
            measCompShowDevices();
            std::puts("SHOWEND");
        }
        else if (!std::strncmp(command, "STATE", 5)) state(port);
        else if (std::sscanf(command, "DOUT %x %x", &digital, &mask) == 2)
            std::printf("RESULT %d\n", writeDigital("DIGITAL_OUTPUT", digital, mask));
        else if (std::sscanf(command, "DIR %x %x", &digital, &mask) == 2)
            std::printf("RESULT %d\n", writeDigital("DIGITAL_DIRECTION", digital, mask));
        else if (std::sscanf(command, "POLL %d", &value) == 1)
            std::printf("RESULT %d\n", pasynFloat64SyncIO->writeOnce("DAQ", 0, value, 2.0, "POLL_SLEEP_MS"));
        else if (std::sscanf(command, "AUTO %d", &value) == 1)
            std::printf("RESULT %d\n", asynAutoConnect("DAQ", -1, value));
        else if (std::sscanf(command, "ENABLEB %d", &value) == 1)
            std::printf("RESULT %d\n", portB ? asynEnable("DAQ2", -1, value) : -1);
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
        else if (std::sscanf(command, "RECORD %63s", record) == 1) readRecord(record);
        else if (!std::strncmp(command, "MESSAGE", 7)) readMessage();
        else if (!std::strncmp(command, "QUIT", 4)) break;
        else std::puts("UNKNOWN");
    }
    // Every case leaves through epicsExit() so the driver's exit handlers run, as in a production IOC.
    epicsExit(0);
    return 0;
}
