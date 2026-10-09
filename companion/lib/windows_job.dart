import 'dart:ffi';
import 'dart:io';

/// Owns an unnamed Windows job. The launch gate prevents the runner from
/// starting any configured program before assignment. Closing the last handle
/// terminates the complete job, even when the direct child exited already.
class WindowsJob {
  WindowsJob._(this._handle);
  Pointer<Void> _handle;

  static WindowsJob attach(int pid) {
    final kernel = _kernel;
    final job = kernel.createJob(nullptr, nullptr);
    if (job == nullptr) {
      throw const ProcessException('', [], 'Could not create child job.');
    }
    final memory = kernel.allocate(kernel.heap(), 8, sizeOf<_ExtendedLimits>());
    if (memory == nullptr) {
      kernel.close(job);
      throw const ProcessException('', [], 'Could not configure child job.');
    }
    final limits = memory.cast<_ExtendedLimits>();
    limits.ref.basic.limitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    try {
      if (kernel.setInformation(job, 9, memory, sizeOf<_ExtendedLimits>()) ==
          0) {
        throw const ProcessException('', [], 'Could not configure child job.');
      }
      // PROCESS_SET_QUOTA | PROCESS_TERMINATE
      final child = kernel.openProcess(0x0100 | 0x0001, 0, pid);
      if (child == nullptr) {
        throw const ProcessException('', [], 'Could not open child process.');
      }
      try {
        if (kernel.assign(job, child) == 0) {
          throw const ProcessException(
            '',
            [],
            'Could not isolate child process.',
          );
        }
      } finally {
        kernel.close(child);
      }
      return WindowsJob._(job);
    } on Object {
      kernel.close(job);
      rethrow;
    } finally {
      kernel.free(kernel.heap(), 0, memory);
    }
  }

  void close() {
    if (_handle == nullptr) return;
    _kernel.close(_handle);
    _handle = nullptr;
  }
}

final _kernel = _Kernel();

class _Kernel {
  final library = DynamicLibrary.open('kernel32.dll');
  late final createJob = library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Uint16>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Uint16>)
      >('CreateJobObjectW');
  late final setInformation = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Pointer<Void>, Uint32),
        int Function(Pointer<Void>, int, Pointer<Void>, int)
      >('SetInformationJobObject');
  late final openProcess = library
      .lookupFunction<
        Pointer<Void> Function(Uint32, Int32, Uint32),
        Pointer<Void> Function(int, int, int)
      >('OpenProcess');
  late final assign = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Void>),
        int Function(Pointer<Void>, Pointer<Void>)
      >('AssignProcessToJobObject');
  late final close = library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('CloseHandle');
  late final heap = library
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetProcessHeap',
      );
  late final allocate = library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr),
        Pointer<Void> Function(Pointer<Void>, int, int)
      >('HeapAlloc');
  late final free = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)
      >('HeapFree');
}

final class _BasicLimits extends Struct {
  @Int64()
  external int processTime;
  @Int64()
  external int jobTime;
  @Uint32()
  external int limitFlags;
  @UintPtr()
  external int minimumWorkingSet;
  @UintPtr()
  external int maximumWorkingSet;
  @Uint32()
  external int activeProcessLimit;
  @UintPtr()
  external int affinity;
  @Uint32()
  external int priorityClass;
  @Uint32()
  external int schedulingClass;
}

final class _IoCounters extends Struct {
  @Uint64()
  external int readOperations;
  @Uint64()
  external int writeOperations;
  @Uint64()
  external int otherOperations;
  @Uint64()
  external int readBytes;
  @Uint64()
  external int writeBytes;
  @Uint64()
  external int otherBytes;
}

final class _ExtendedLimits extends Struct {
  external _BasicLimits basic;
  external _IoCounters counters;
  @UintPtr()
  external int processMemory;
  @UintPtr()
  external int jobMemory;
  @UintPtr()
  external int peakProcessMemory;
  @UintPtr()
  external int peakJobMemory;
}
