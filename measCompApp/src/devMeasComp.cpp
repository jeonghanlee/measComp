/* Analog input conversion with confirmed device bounds. */
#define USE_TYPED_DSET
#include <map>
#include <aiRecord.h>
#include <alarm.h>
#include <dbAccess.h>
#include <epicsGuard.h>
#include <epicsMutex.h>
#include <menuConvert.h>
#include <recGbl.h>
#include <registryDeviceSupport.h>
#include <asynDriver.h>
#include <asynEpicsUtils.h>
#include <asynInt32SyncIO.h>
#include <epicsExport.h>

namespace {

struct Bounds {
    asynUser *user;
    epicsInt32 low;
    epicsInt32 high;
    bool confirmed;
    Bounds() : user(0), low(0), high(0), confirmed(false) {}
};

aidset *averageSupport = 0;
epicsMutex boundsMutex;
std::map<aiRecord *, Bounds *> boundsByRecord;

// Record state has IOC lifetime, as does the delegated asyn callback state.
// The registry lock is never held across a port call or a delegated routine.
Bounds *findBounds(aiRecord *record)
{
    epicsGuard<epicsMutex> guard(boundsMutex);
    std::map<aiRecord *, Bounds *>::iterator found = boundsByRecord.find(record);
    return found == boundsByRecord.end() ? 0 : found->second;
}

bool convert(aiRecord *record, Bounds *bounds)
{
    if (!bounds) return false;
    if (!bounds->confirmed) {
        epicsInt32 low = 0, high = 0;
        if (pasynInt32SyncIO->getBounds(bounds->user, &low, &high) != asynSuccess || high <= low)
            return false;
        bounds->low = low;
        bounds->high = high;
        bounds->confirmed = true;
    }
    if (record->linr == menuConvertLINEAR) {
        double low = bounds->low, high = bounds->high;
        record->eslo = (record->eguf - record->egul) / (high - low);
        record->eoff = (high * record->egul - low * record->eguf) / (high - low);
    }
    return true;
}

long initSupport(int after)
{
    if (after) return 0;
    averageSupport = reinterpret_cast<aidset *>(registryDeviceSupportFind("asynAiInt32Average"));
    if (!averageSupport || averageSupport->common.number < 6 ||
        !averageSupport->common.init_record || !averageSupport->common.get_ioint_info ||
        !averageSupport->read_ai) {
        averageSupport = 0;
        return S_dev_missingSup;
    }
    return 0;
}

long initRecord(dbCommon *common)
{
    aiRecord *record = reinterpret_cast<aiRecord *>(common);
    if (!averageSupport) {
        recGblRecordError(S_dev_missingSup, record, "measCompInt32Average requires asynInt32Average");
        record->pact = 1;
        return S_dev_missingSup;
    }
    Bounds *bounds = new Bounds;
    asynUser *parser = pasynManager->createAsynUser(0, 0);
    char *port = 0, *parameter = 0;
    int address = 0;
    asynStatus status = pasynEpicsUtils->parseLink(parser, &record->inp, &port, &address, &parameter);
    if (status == asynSuccess)
        status = pasynInt32SyncIO->connect(port, address, &bounds->user, parameter);
    if (status == asynSuccess) bounds->user->timeout = parser->timeout;
    pasynEpicsUtils->parseLinkFree(parser, &port, &parameter);
    pasynManager->freeAsynUser(parser);
    if (status != asynSuccess) {
        if (bounds->user) pasynInt32SyncIO->disconnect(bounds->user);
        delete bounds;
        recGblRecordError(S_dev_badInpType, record, "measCompInt32Average requires an @asyn input link");
        record->pact = 1;
        return S_dev_badInpType;
    }

    // asyn owns dpvt and all averaging/interrupt state; only use its public DSET.
    long result = averageSupport->common.init_record(common);
    if (result) {
        pasynInt32SyncIO->disconnect(bounds->user);
        delete bounds;
        return result;
    }
    {
        epicsGuard<epicsMutex> guard(boundsMutex);
        boundsByRecord[record] = bounds;
    }
    convert(record, bounds);
    return 0;
}

long getIoIntInfo(int detach, dbCommon *common, IOSCANPVT *scan)
{
    if (!findBounds(reinterpret_cast<aiRecord *>(common))) return -1;
    return averageSupport->common.get_ioint_info(detach, common, scan);
}

long readAi(aiRecord *record)
{
    Bounds *bounds = findBounds(record);
    if (!bounds) return -1;
    bool validBounds = convert(record, bounds);
    long status = averageSupport->read_ai(record);
    if (record->linr == menuConvertLINEAR && !validBounds) {
        recGblSetSevr(record, READ_ALARM, INVALID_ALARM);
        record->udf = 1;
        return status ? status : -1;
    }
    return status;
}

long specialLinconv(aiRecord *record, int after)
{
    if (after) convert(record, findBounds(record));
    return 0;
}

}

extern "C" {
aidset measCompAiInt32Average = {
    {6, 0, initSupport, initRecord, getIoIntInfo}, readAi, specialLinconv
};
epicsExportAddress(dset, measCompAiInt32Average);
}
