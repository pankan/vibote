// Vibote Mic: a minimal Core Audio HAL plug-in providing a loopback device.
// Vibote plays remote-microphone audio to the device's output; other apps
// (e.g. Wispr Flow) record it from the device's input. Mono, 48 kHz, Float32.

#include <CoreAudio/AudioServerPlugIn.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdatomic.h>
#include <string.h>
#include <stddef.h>

enum {
    kObjectID_PlugIn = kAudioObjectPlugInObject,
    kObjectID_Device = 2,
    kObjectID_StreamInput = 3,
    kObjectID_StreamOutput = 4,
};

#define kDeviceName        "Vibote Mic"
#define kManufacturer      "Vibote"
#define kDeviceUID         "ViboteMic_UID"
#define kModelUID          "ViboteMic_Model"
#define kSampleRate        48000.0
#define kChannels          1
#define kRingFrames        16384  // also the zero-timestamp period
#define kLatencyFrames     0
#define kSafetyOffset      0

static AudioServerPlugInHostRef gHost = NULL;
static pthread_mutex_t gStateMutex = PTHREAD_MUTEX_INITIALIZER;
static UInt32 gRefCount = 0;
static UInt64 gIOCount = 0;
static Float64 gHostTicksPerFrame = 0;
static UInt64 gAnchorHostTime = 0;
static UInt64 gTimestampCount = 0;
static _Atomic(Float32) gRing[kRingFrames * kChannels];

#pragma mark Forward declarations

static HRESULT QueryInterface(void*, REFIID, LPVOID*);
static ULONG AddRef(void*);
static ULONG Release(void*);
static OSStatus Initialize(AudioServerPlugInDriverRef, AudioServerPlugInHostRef);
static OSStatus CreateDevice(AudioServerPlugInDriverRef, CFDictionaryRef, const AudioServerPlugInClientInfo*, AudioObjectID*);
static OSStatus DestroyDevice(AudioServerPlugInDriverRef, AudioObjectID);
static OSStatus AddDeviceClient(AudioServerPlugInDriverRef, AudioObjectID, const AudioServerPlugInClientInfo*);
static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef, AudioObjectID, const AudioServerPlugInClientInfo*);
static OSStatus PerformDeviceConfigurationChange(AudioServerPlugInDriverRef, AudioObjectID, UInt64, void*);
static OSStatus AbortDeviceConfigurationChange(AudioServerPlugInDriverRef, AudioObjectID, UInt64, void*);
static Boolean HasProperty(AudioServerPlugInDriverRef, AudioObjectID, pid_t, const AudioObjectPropertyAddress*);
static OSStatus IsPropertySettable(AudioServerPlugInDriverRef, AudioObjectID, pid_t, const AudioObjectPropertyAddress*, Boolean*);
static OSStatus GetPropertyDataSize(AudioServerPlugInDriverRef, AudioObjectID, pid_t, const AudioObjectPropertyAddress*, UInt32, const void*, UInt32*);
static OSStatus GetPropertyData(AudioServerPlugInDriverRef, AudioObjectID, pid_t, const AudioObjectPropertyAddress*, UInt32, const void*, UInt32, UInt32*, void*);
static OSStatus SetPropertyData(AudioServerPlugInDriverRef, AudioObjectID, pid_t, const AudioObjectPropertyAddress*, UInt32, const void*, UInt32, const void*);
static OSStatus StartIO(AudioServerPlugInDriverRef, AudioObjectID, UInt32);
static OSStatus StopIO(AudioServerPlugInDriverRef, AudioObjectID, UInt32);
static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef, AudioObjectID, UInt32, Float64*, UInt64*, UInt64*);
static OSStatus WillDoIOOperation(AudioServerPlugInDriverRef, AudioObjectID, UInt32, UInt32, Boolean*, Boolean*);
static OSStatus BeginIOOperation(AudioServerPlugInDriverRef, AudioObjectID, UInt32, UInt32, UInt32, const AudioServerPlugInIOCycleInfo*);
static OSStatus DoIOOperation(AudioServerPlugInDriverRef, AudioObjectID, AudioObjectID, UInt32, UInt32, UInt32, const AudioServerPlugInIOCycleInfo*, void*, void*);
static OSStatus EndIOOperation(AudioServerPlugInDriverRef, AudioObjectID, UInt32, UInt32, UInt32, const AudioServerPlugInIOCycleInfo*);

static AudioServerPlugInDriverInterface gInterface = {
    NULL, QueryInterface, AddRef, Release, Initialize, CreateDevice, DestroyDevice,
    AddDeviceClient, RemoveDeviceClient, PerformDeviceConfigurationChange, AbortDeviceConfigurationChange,
    HasProperty, IsPropertySettable, GetPropertyDataSize, GetPropertyData, SetPropertyData,
    StartIO, StopIO, GetZeroTimeStamp, WillDoIOOperation, BeginIOOperation, DoIOOperation, EndIOOperation
};
static AudioServerPlugInDriverInterface* gInterfacePtr = &gInterface;
static AudioServerPlugInDriverRef gDriverRef = &gInterfacePtr;

#pragma mark Factory and COM

void* ViboteMic_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID) {
    (void)allocator;
    return CFEqual(requestedTypeUUID, kAudioServerPlugInTypeUUID) ? gDriverRef : NULL;
}

static HRESULT QueryInterface(void* driver, REFIID iid, LPVOID* out) {
    if (driver != gDriverRef || out == NULL) return kAudioHardwareBadObjectError;
    CFUUIDRef requested = CFUUIDCreateFromUUIDBytes(NULL, iid);
    HRESULT result = E_NOINTERFACE;
    if (CFEqual(requested, IUnknownUUID) || CFEqual(requested, kAudioServerPlugInDriverInterfaceUUID)) {
        pthread_mutex_lock(&gStateMutex); gRefCount++; pthread_mutex_unlock(&gStateMutex);
        *out = gDriverRef; result = S_OK;
    }
    CFRelease(requested);
    return result;
}
static ULONG AddRef(void* driver) {
    if (driver != gDriverRef) return 0;
    pthread_mutex_lock(&gStateMutex); ULONG count = ++gRefCount; pthread_mutex_unlock(&gStateMutex);
    return count;
}
static ULONG Release(void* driver) {
    if (driver != gDriverRef) return 0;
    pthread_mutex_lock(&gStateMutex); if (gRefCount > 0) gRefCount--; ULONG count = gRefCount; pthread_mutex_unlock(&gStateMutex);
    return count;
}

static OSStatus Initialize(AudioServerPlugInDriverRef driver, AudioServerPlugInHostRef host) {
    if (driver != gDriverRef) return kAudioHardwareBadObjectError;
    gHost = host;
    mach_timebase_info_data_t timebase; mach_timebase_info(&timebase);
    Float64 hostClockFrequency = ((Float64)timebase.denom / (Float64)timebase.numer) * 1000000000.0;
    gHostTicksPerFrame = hostClockFrequency / kSampleRate;
    return 0;
}
static OSStatus CreateDevice(AudioServerPlugInDriverRef d, CFDictionaryRef desc, const AudioServerPlugInClientInfo* c, AudioObjectID* out) { (void)d; (void)desc; (void)c; (void)out; return kAudioHardwareUnsupportedOperationError; }
static OSStatus DestroyDevice(AudioServerPlugInDriverRef d, AudioObjectID o) { (void)d; (void)o; return kAudioHardwareUnsupportedOperationError; }
static OSStatus AddDeviceClient(AudioServerPlugInDriverRef d, AudioObjectID o, const AudioServerPlugInClientInfo* c) { (void)d; (void)o; (void)c; return 0; }
static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef d, AudioObjectID o, const AudioServerPlugInClientInfo* c) { (void)d; (void)o; (void)c; return 0; }
static OSStatus PerformDeviceConfigurationChange(AudioServerPlugInDriverRef d, AudioObjectID o, UInt64 a, void* i) { (void)d; (void)o; (void)a; (void)i; return 0; }
static OSStatus AbortDeviceConfigurationChange(AudioServerPlugInDriverRef d, AudioObjectID o, UInt64 a, void* i) { (void)d; (void)o; (void)a; (void)i; return 0; }

#pragma mark Properties

static AudioStreamBasicDescription StreamFormat(void) {
    AudioStreamBasicDescription f = {0};
    f.mSampleRate = kSampleRate;
    f.mFormatID = kAudioFormatLinearPCM;
    f.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    f.mBytesPerPacket = 4 * kChannels; f.mFramesPerPacket = 1; f.mBytesPerFrame = 4 * kChannels;
    f.mChannelsPerFrame = kChannels; f.mBitsPerChannel = 32;
    return f;
}

static Boolean IsStream(AudioObjectID id) { return id == kObjectID_StreamInput || id == kObjectID_StreamOutput; }

static Boolean HasProperty(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress* a) {
    (void)pid;
    if (driver != gDriverRef || a == NULL) return false;
    switch (id) {
    case kObjectID_PlugIn:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: case kAudioObjectPropertyClass: case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyManufacturer: case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList: case kAudioPlugInPropertyTranslateUIDToDevice: case kAudioPlugInPropertyResourceBundle:
            return true;
        }
        return false;
    case kObjectID_Device:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: case kAudioObjectPropertyClass: case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyName: case kAudioObjectPropertyManufacturer: case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyDeviceUID: case kAudioDevicePropertyModelUID: case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyRelatedDevices: case kAudioDevicePropertyClockDomain: case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning: case kAudioObjectPropertyControlList: case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyAvailableNominalSampleRates: case kAudioDevicePropertyIsHidden: case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyStreams: case kAudioDevicePropertyClockIsStable:
            return true;
        case kAudioDevicePropertyDeviceCanBeDefaultDevice: case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyLatency: case kAudioDevicePropertySafetyOffset: case kAudioDevicePropertyPreferredChannelsForStereo:
            return a->mScope == kAudioObjectPropertyScopeInput || a->mScope == kAudioObjectPropertyScopeOutput || a->mScope == kAudioObjectPropertyScopeGlobal;
        }
        return false;
    case kObjectID_StreamInput: case kObjectID_StreamOutput:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: case kAudioObjectPropertyClass: case kAudioObjectPropertyOwner: case kAudioObjectPropertyOwnedObjects:
        case kAudioStreamPropertyIsActive: case kAudioStreamPropertyDirection: case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel: case kAudioStreamPropertyLatency: case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: case kAudioStreamPropertyAvailableVirtualFormats: case kAudioStreamPropertyAvailablePhysicalFormats:
            return true;
        }
        return false;
    }
    return false;
}

static OSStatus IsPropertySettable(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress* a, Boolean* out) {
    if (!HasProperty(driver, id, pid, a) || out == NULL) return kAudioHardwareUnknownPropertyError;
    // Formats and rates are fixed; accept writes of the same value but report as settable for stream formats so hosts don't fail.
    *out = IsStream(id) && (a->mSelector == kAudioStreamPropertyVirtualFormat || a->mSelector == kAudioStreamPropertyPhysicalFormat || a->mSelector == kAudioStreamPropertyIsActive);
    return 0;
}

static OSStatus GetPropertyDataSize(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress* a, UInt32 qs, const void* qd, UInt32* out) {
    if (out == NULL) return kAudioHardwareIllegalOperationError;
    UInt32 dataSize = 0;
    // Reuse GetPropertyData with a large scratch buffer to compute sizes consistently.
    union { max_align_t alignment; UInt8 bytes[256]; } scratch;
    OSStatus status = GetPropertyData(driver, id, pid, a, qs, qd, sizeof(scratch), &dataSize, &scratch);
    if (status == 0) *out = dataSize;
    // Release any CF object we just produced.
    if (status == 0 && dataSize == sizeof(CFTypeRef)) {
        switch (a->mSelector) {
        case kAudioObjectPropertyName: case kAudioObjectPropertyManufacturer: case kAudioDevicePropertyDeviceUID: case kAudioDevicePropertyModelUID: case kAudioPlugInPropertyResourceBundle:
            CFRelease(*(CFTypeRef*)scratch.bytes); break;
        }
    }
    return status;
}

#define WRITE(type, value) do { if (inSize < sizeof(type)) return kAudioHardwareBadPropertySizeError; *(type*)out = (value); *outSize = sizeof(type); return 0; } while (0)

static OSStatus GetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress* a, UInt32 qs, const void* qd, UInt32 inSize, UInt32* outSize, void* out) {
    (void)pid;
    if (driver != gDriverRef || a == NULL || outSize == NULL || out == NULL) return kAudioHardwareIllegalOperationError;
    switch (id) {
    case kObjectID_PlugIn:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: WRITE(AudioClassID, kAudioObjectClassID);
        case kAudioObjectPropertyClass: WRITE(AudioClassID, kAudioPlugInClassID);
        case kAudioObjectPropertyOwner: WRITE(AudioObjectID, kAudioObjectUnknown);
        case kAudioObjectPropertyManufacturer: WRITE(CFStringRef, CFSTR(kManufacturer));
        case kAudioObjectPropertyOwnedObjects: case kAudioPlugInPropertyDeviceList:
            if (inSize < sizeof(AudioObjectID)) { *outSize = 0; return 0; }
            WRITE(AudioObjectID, kObjectID_Device);
        case kAudioPlugInPropertyTranslateUIDToDevice: {
            if (qs != sizeof(CFStringRef) || qd == NULL) return kAudioHardwareBadPropertySizeError;
            CFStringRef uid = *(const CFStringRef*)qd;
            WRITE(AudioObjectID, CFStringCompare(uid, CFSTR(kDeviceUID), 0) == kCFCompareEqualTo ? kObjectID_Device : kAudioObjectUnknown);
        }
        case kAudioPlugInPropertyResourceBundle: WRITE(CFStringRef, CFSTR(""));
        }
        break;
    case kObjectID_Device:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: WRITE(AudioClassID, kAudioObjectClassID);
        case kAudioObjectPropertyClass: WRITE(AudioClassID, kAudioDeviceClassID);
        case kAudioObjectPropertyOwner: WRITE(AudioObjectID, kObjectID_PlugIn);
        case kAudioObjectPropertyName: WRITE(CFStringRef, CFSTR(kDeviceName));
        case kAudioObjectPropertyManufacturer: WRITE(CFStringRef, CFSTR(kManufacturer));
        case kAudioDevicePropertyDeviceUID: WRITE(CFStringRef, CFSTR(kDeviceUID));
        case kAudioDevicePropertyModelUID: WRITE(CFStringRef, CFSTR(kModelUID));
        case kAudioDevicePropertyTransportType: WRITE(UInt32, kAudioDeviceTransportTypeVirtual);
        case kAudioDevicePropertyRelatedDevices: WRITE(AudioObjectID, kObjectID_Device);
        case kAudioDevicePropertyClockDomain: WRITE(UInt32, 0);
        case kAudioDevicePropertyDeviceIsAlive: WRITE(UInt32, 1);
        case kAudioDevicePropertyDeviceIsRunning: { pthread_mutex_lock(&gStateMutex); UInt32 running = gIOCount > 0; pthread_mutex_unlock(&gStateMutex); WRITE(UInt32, running); }
        // Offer it as a microphone, never as the system output.
        case kAudioDevicePropertyDeviceCanBeDefaultDevice: WRITE(UInt32, a->mScope == kAudioObjectPropertyScopeInput ? 1 : 0);
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: WRITE(UInt32, 0);
        case kAudioDevicePropertyLatency: WRITE(UInt32, kLatencyFrames);
        case kAudioDevicePropertySafetyOffset: WRITE(UInt32, kSafetyOffset);
        case kAudioDevicePropertyNominalSampleRate: WRITE(Float64, kSampleRate);
        case kAudioDevicePropertyAvailableNominalSampleRates: { AudioValueRange r = { kSampleRate, kSampleRate }; WRITE(AudioValueRange, r); }
        case kAudioDevicePropertyIsHidden: WRITE(UInt32, 0);
        case kAudioDevicePropertyZeroTimeStampPeriod: WRITE(UInt32, kRingFrames);
        case kAudioDevicePropertyClockIsStable: WRITE(UInt32, 1);
        case kAudioDevicePropertyPreferredChannelsForStereo: {
            if (inSize < 2 * sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            ((UInt32*)out)[0] = 1; ((UInt32*)out)[1] = 1; *outSize = 2 * sizeof(UInt32); return 0;
        }
        case kAudioObjectPropertyControlList: *outSize = 0; return 0;
        case kAudioObjectPropertyOwnedObjects: case kAudioDevicePropertyStreams: {
            AudioObjectID ids[2]; UInt32 n = 0;
            if (a->mScope != kAudioObjectPropertyScopeOutput) ids[n++] = kObjectID_StreamInput;
            if (a->mScope != kAudioObjectPropertyScopeInput) ids[n++] = kObjectID_StreamOutput;
            UInt32 fit = inSize / sizeof(AudioObjectID); if (fit < n) n = fit;
            memcpy(out, ids, n * sizeof(AudioObjectID)); *outSize = n * sizeof(AudioObjectID); return 0;
        }
        }
        break;
    case kObjectID_StreamInput: case kObjectID_StreamOutput:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: WRITE(AudioClassID, kAudioObjectClassID);
        case kAudioObjectPropertyClass: WRITE(AudioClassID, kAudioStreamClassID);
        case kAudioObjectPropertyOwner: WRITE(AudioObjectID, kObjectID_Device);
        case kAudioObjectPropertyOwnedObjects: *outSize = 0; return 0;
        case kAudioStreamPropertyIsActive: WRITE(UInt32, 1);
        case kAudioStreamPropertyDirection: WRITE(UInt32, id == kObjectID_StreamInput ? 1 : 0);
        case kAudioStreamPropertyTerminalType: WRITE(UInt32, id == kObjectID_StreamInput ? kAudioStreamTerminalTypeMicrophone : kAudioStreamTerminalTypeSpeaker);
        case kAudioStreamPropertyStartingChannel: WRITE(UInt32, 1);
        case kAudioStreamPropertyLatency: WRITE(UInt32, kLatencyFrames);
        case kAudioStreamPropertyVirtualFormat: case kAudioStreamPropertyPhysicalFormat: WRITE(AudioStreamBasicDescription, StreamFormat());
        case kAudioStreamPropertyAvailableVirtualFormats: case kAudioStreamPropertyAvailablePhysicalFormats: {
            AudioStreamRangedDescription r; r.mFormat = StreamFormat(); r.mSampleRateRange.mMinimum = kSampleRate; r.mSampleRateRange.mMaximum = kSampleRate;
            if (inSize < sizeof(r)) { *outSize = 0; return 0; }
            WRITE(AudioStreamRangedDescription, r);
        }
        }
        break;
    }
    return kAudioHardwareUnknownPropertyError;
}

static OSStatus SetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress* a, UInt32 qs, const void* qd, UInt32 size, const void* data) {
    (void)pid; (void)qs; (void)qd;
    if (driver != gDriverRef) return kAudioHardwareBadObjectError;
    if (a == NULL || data == NULL) return kAudioHardwareIllegalOperationError;
    if (IsStream(id) && (a->mSelector == kAudioStreamPropertyVirtualFormat || a->mSelector == kAudioStreamPropertyPhysicalFormat)) {
        if (size < sizeof(AudioStreamBasicDescription)) return kAudioHardwareBadPropertySizeError;
        const AudioStreamBasicDescription* f = data;
        return (f->mSampleRate == kSampleRate && f->mChannelsPerFrame == kChannels &&
                f->mFormatID == kAudioFormatLinearPCM && f->mFormatFlags == StreamFormat().mFormatFlags &&
                f->mBytesPerPacket == 4 * kChannels && f->mFramesPerPacket == 1 &&
                f->mBytesPerFrame == 4 * kChannels && f->mBitsPerChannel == 32) ? 0 : kAudioDeviceUnsupportedFormatError;
    }
    if (IsStream(id) && a->mSelector == kAudioStreamPropertyIsActive) return 0;
    return kAudioHardwareUnknownPropertyError;
}

#pragma mark IO

static OSStatus StartIO(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 client) {
    (void)client;
    if (driver != gDriverRef || id != kObjectID_Device) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&gStateMutex);
    if (gIOCount++ == 0) { gTimestampCount = 0; gAnchorHostTime = mach_absolute_time(); for (UInt32 i = 0; i < kRingFrames * kChannels; i++) atomic_store_explicit(&gRing[i], 0, memory_order_relaxed); }
    pthread_mutex_unlock(&gStateMutex);
    return 0;
}
static OSStatus StopIO(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 client) {
    (void)client;
    if (driver != gDriverRef || id != kObjectID_Device) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&gStateMutex); if (gIOCount > 0) gIOCount--; pthread_mutex_unlock(&gStateMutex);
    return 0;
}
static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 client, Float64* sampleTime, UInt64* hostTime, UInt64* seed) {
    (void)client;
    if (driver != gDriverRef || id != kObjectID_Device) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&gStateMutex);
    UInt64 now = mach_absolute_time();
    Float64 ticksPerPeriod = gHostTicksPerFrame * kRingFrames;
    // Catch up in one step after a long scheduling gap or wake from sleep.
    gTimestampCount = (UInt64)((Float64)(now - gAnchorHostTime) / ticksPerPeriod);
    *sampleTime = (Float64)(gTimestampCount * kRingFrames);
    *hostTime = gAnchorHostTime + (UInt64)((Float64)gTimestampCount * ticksPerPeriod);
    *seed = 1;
    pthread_mutex_unlock(&gStateMutex);
    return 0;
}
static OSStatus WillDoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID id, UInt32 client, UInt32 op, Boolean* will, Boolean* inPlace) {
    (void)client;
    if (driver != gDriverRef || id != kObjectID_Device) return kAudioHardwareBadObjectError;
    *will = op == kAudioServerPlugInIOOperationReadInput || op == kAudioServerPlugInIOOperationWriteMix;
    *inPlace = true;
    return 0;
}
static OSStatus BeginIOOperation(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 c, UInt32 op, UInt32 n, const AudioServerPlugInIOCycleInfo* i) { (void)d; (void)o; (void)c; (void)op; (void)n; (void)i; return 0; }
static OSStatus EndIOOperation(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 c, UInt32 op, UInt32 n, const AudioServerPlugInIOCycleInfo* i) { (void)d; (void)o; (void)c; (void)op; (void)n; (void)i; return 0; }

static OSStatus DoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID id, AudioObjectID stream, UInt32 client, UInt32 op, UInt32 frames, const AudioServerPlugInIOCycleInfo* cycle, void* main, void* secondary) {
    (void)stream; (void)client; (void)secondary;
    if (driver != gDriverRef || id != kObjectID_Device) return kAudioHardwareBadObjectError;
    Float32* buffer = main;
    if (op == kAudioServerPlugInIOOperationWriteMix) {
        UInt64 start = (UInt64)cycle->mOutputTime.mSampleTime;
        for (UInt32 f = 0; f < frames; f++) atomic_store_explicit(&gRing[(start + f) % kRingFrames], buffer[f], memory_order_relaxed);
    } else if (op == kAudioServerPlugInIOOperationReadInput) {
        UInt64 start = (UInt64)cycle->mInputTime.mSampleTime;
        // Read, then clear, so the input goes silent when nothing is being played instead of looping stale audio.
        for (UInt32 f = 0; f < frames; f++) { UInt64 i = (start + f) % kRingFrames; buffer[f] = atomic_exchange_explicit(&gRing[i], 0, memory_order_relaxed); }
    }
    return 0;
}
