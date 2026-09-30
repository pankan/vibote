// Exercise the HAL callbacks without loading a driver into coreaudiod.
#include "../Driver/ViboteMic.c"
#include <assert.h>
#include <stdio.h>

int main(void) {
    assert(Initialize(gDriverRef, NULL) == 0);
    AudioObjectPropertyAddress address = { kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    assert(GetPropertyDataSize(gDriverRef, kObjectID_StreamInput, 0, &address, 0, NULL, NULL) != 0);
    UInt32 size = 0;
    assert(GetPropertyDataSize(gDriverRef, kObjectID_StreamInput, 0, &address, 0, NULL, &size) == 0);
    assert(size == sizeof(AudioStreamBasicDescription));
    AudioStreamBasicDescription format = StreamFormat();
    assert(SetPropertyData(gDriverRef, kObjectID_StreamInput, 0, &address, 0, NULL, sizeof(format), &format) == 0);
    format.mBitsPerChannel = 16;
    assert(SetPropertyData(gDriverRef, kObjectID_StreamInput, 0, &address, 0, NULL, sizeof(format), &format) == kAudioDeviceUnsupportedFormatError);
    assert(SetPropertyData(gDriverRef, kObjectID_StreamInput, 0, &address, 0, NULL, sizeof(format), NULL) != 0);
    assert(atomic_is_lock_free(&gRing[0]));
    assert(StartIO(gDriverRef, kObjectID_Device, 0) == 0);
    AudioServerPlugInIOCycleInfo cycle = {0};
    cycle.mOutputTime.mSampleTime = kRingFrames - 2;
    cycle.mInputTime.mSampleTime = kRingFrames - 2;
    Float32 values[] = {0.1f, -0.2f, 0.3f, -0.4f}, captured[4] = {0};
    assert(DoIOOperation(gDriverRef, kObjectID_Device, kObjectID_StreamOutput, 0, kAudioServerPlugInIOOperationWriteMix, 4, &cycle, values, NULL) == 0);
    assert(DoIOOperation(gDriverRef, kObjectID_Device, kObjectID_StreamInput, 0, kAudioServerPlugInIOOperationReadInput, 4, &cycle, captured, NULL) == 0);
    for (int i = 0; i < 4; i++) assert(captured[i] == values[i]);
    DoIOOperation(gDriverRef, kObjectID_Device, kObjectID_StreamInput, 0, kAudioServerPlugInIOOperationReadInput, 4, &cycle, captured, NULL);
    for (int i = 0; i < 4; i++) assert(captured[i] == 0);
    gAnchorHostTime = mach_absolute_time() - (UInt64)(gHostTicksPerFrame * kRingFrames * 5.5);
    Float64 sampleTime; UInt64 hostTime, seed;
    assert(GetZeroTimeStamp(gDriverRef, kObjectID_Device, 0, &sampleTime, &hostTime, &seed) == 0);
    assert(sampleTime >= 5 * kRingFrames);
    assert(StopIO(gDriverRef, kObjectID_Device, 0) == 0);
    puts("Driver checks passed: format validation, ring wrap, silence, clock recovery");
}
