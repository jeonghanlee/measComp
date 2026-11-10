< envPaths

## Register all support components
dbLoadDatabase "$(MEASCOMP)/dbd/measCompApp.dbd"
measCompApp_registerRecordDeviceDriver pdbbase

epicsEnvSet("PREFIX",        "TC32:")
epicsEnvSet("PORT",          "TC32_1")
epicsEnvSet("UNIQUE_ID",     "164.54.160.221")

## Configure port driver
# MultiFunctionConfig((portName,        # The name to give to this asyn port driver
#                      uniqueID,        # For USB the serial number.  For Ethernet the MAC address or IP address.
#                      maxInputPoints,  # Maximum number of input points for waveform digitizer
#                      maxOutputPoints) # Maximum number of output points for waveform generator
MultiFunctionConfig("$(PORT)", "$(UNIQUE_ID)", 1, 1)

#asynSetTraceMask($(PORT), -1, ERROR|FLOW|DRIVER)

dbLoadTemplate("$(MEASCOMP)/db/TC32.substitutions", "P=$(PREFIX),PORT=$(PORT)")

## Network TC32 only: the cold-junction temperatures, the mains rejection frequency, the calibration table
## and the calibration dates. Enable this line for a TC32 reached over Ethernet; do not enable it for a
## USB TC-32, whose driver rejects these settings.
#dbLoadTemplate("$(MEASCOMP)/db/TC32Network.substitutions", "P=$(PREFIX),PORT=$(PORT)")

< ../save_restore.cmd

iocInit

create_monitor_set("auto_settings.req",30,"P=$(PREFIX)")
