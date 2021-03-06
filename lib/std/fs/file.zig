const std = @import("../std.zig");
const builtin = @import("builtin");
const os = std.os;
const io = std.io;
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;
const windows = os.windows;
const Os = builtin.Os;
const maxInt = std.math.maxInt;
const need_async_thread = std.fs.need_async_thread;

pub const File = struct {
    /// The OS-specific file descriptor or file handle.
    handle: os.fd_t,

    /// On some systems, such as Linux, file system file descriptors are incapable of non-blocking I/O.
    /// This forces us to perform asynchronous I/O on a dedicated thread, to achieve non-blocking
    /// file-system I/O. To do this, `File` must be aware of whether it is a file system file descriptor,
    /// or, more specifically, whether the I/O is blocking.
    io_mode: io.Mode,

    /// Even when 'std.io.mode' is async, it is still sometimes desirable to perform blocking I/O, although
    /// not by default. For example, when printing a stack trace to stderr.
    async_block_allowed: @TypeOf(async_block_allowed_no) = async_block_allowed_no,

    pub const async_block_allowed_yes = if (io.is_async) true else {};
    pub const async_block_allowed_no = if (io.is_async) false else {};

    pub const Mode = os.mode_t;

    pub const default_mode = switch (builtin.os.tag) {
        .windows => 0,
        else => 0o666,
    };

    pub const OpenError = windows.CreateFileError || os.OpenError || os.FlockError;

    pub const Lock = enum {
        None, Shared, Exclusive
    };

    /// TODO https://github.com/ziglang/zig/issues/3802
    pub const OpenFlags = struct {
        read: bool = true,
        write: bool = false,

        /// Open the file with a lock to prevent other processes from accessing it at the
        /// same time. An exclusive lock will prevent other processes from acquiring a lock.
        /// A shared lock will prevent other processes from acquiring a exclusive lock, but
        /// doesn't prevent other process from getting their own shared locks.
        ///
        /// Note that the lock is only advisory on Linux, except in very specific cirsumstances[1].
        /// This means that a process that does not respect the locking API can still get access
        /// to the file, despite the lock.
        ///
        /// Windows' file locks are mandatory, and any process attempting to access the file will
        /// receive an error.
        ///
        /// [1]: https://www.kernel.org/doc/Documentation/filesystems/mandatory-locking.txt
        lock: Lock = .None,

        /// Sets whether or not to wait until the file is locked to return. If set to true,
        /// `error.WouldBlock` will be returned. Otherwise, the file will wait until the file
        /// is available to proceed.
        lock_nonblocking: bool = false,

        /// This prevents `O_NONBLOCK` from being passed even if `std.io.is_async`.
        /// It allows the use of `noasync` when calling functions related to opening
        /// the file, reading, and writing.
        always_blocking: bool = false,
    };

    /// TODO https://github.com/ziglang/zig/issues/3802
    pub const CreateFlags = struct {
        /// Whether the file will be created with read access.
        read: bool = false,

        /// If the file already exists, and is a regular file, and the access
        /// mode allows writing, it will be truncated to length 0.
        truncate: bool = true,

        /// Ensures that this open call creates the file, otherwise causes
        /// `error.FileAlreadyExists` to be returned.
        exclusive: bool = false,

        /// Open the file with a lock to prevent other processes from accessing it at the
        /// same time. An exclusive lock will prevent other processes from acquiring a lock.
        /// A shared lock will prevent other processes from acquiring a exclusive lock, but
        /// doesn't prevent other process from getting their own shared locks.
        ///
        /// Note that the lock is only advisory on Linux, except in very specific cirsumstances[1].
        /// This means that a process that does not respect the locking API can still get access
        /// to the file, despite the lock.
        ///
        /// Windows's file locks are mandatory, and any process attempting to access the file will
        /// receive an error.
        ///
        /// [1]: https://www.kernel.org/doc/Documentation/filesystems/mandatory-locking.txt
        lock: Lock = .None,

        /// Sets whether or not to wait until the file is locked to return. If set to true,
        /// `error.WouldBlock` will be returned. Otherwise, the file will wait until the file
        /// is available to proceed.
        lock_nonblocking: bool = false,

        /// For POSIX systems this is the file system mode the file will
        /// be created with.
        mode: Mode = default_mode,
    };

    /// Upon success, the stream is in an uninitialized state. To continue using it,
    /// you must use the open() function.
    pub fn close(self: File) void {
        if (need_async_thread and self.io_mode == .blocking and !self.async_block_allowed) {
            std.event.Loop.instance.?.close(self.handle);
        } else {
            os.close(self.handle);
        }
    }

    /// Test whether the file refers to a terminal.
    /// See also `supportsAnsiEscapeCodes`.
    pub fn isTty(self: File) bool {
        return os.isatty(self.handle);
    }

    /// Test whether ANSI escape codes will be treated as such.
    pub fn supportsAnsiEscapeCodes(self: File) bool {
        if (builtin.os.tag == .windows) {
            return os.isCygwinPty(self.handle);
        }
        if (self.isTty()) {
            if (self.handle == os.STDOUT_FILENO or self.handle == os.STDERR_FILENO) {
                // Use getenvC to workaround https://github.com/ziglang/zig/issues/3511
                if (os.getenvZ("TERM")) |term| {
                    if (std.mem.eql(u8, term, "dumb"))
                        return false;
                }
            }
            return true;
        }
        return false;
    }

    pub const SetEndPosError = os.TruncateError;

    /// Shrinks or expands the file.
    /// The file offset after this call is left unchanged.
    pub fn setEndPos(self: File, length: u64) SetEndPosError!void {
        try os.ftruncate(self.handle, length);
    }

    pub const SeekError = os.SeekError;

    /// Repositions read/write file offset relative to the current offset.
    /// TODO: integrate with async I/O
    pub fn seekBy(self: File, offset: i64) SeekError!void {
        return os.lseek_CUR(self.handle, offset);
    }

    /// Repositions read/write file offset relative to the end.
    /// TODO: integrate with async I/O
    pub fn seekFromEnd(self: File, offset: i64) SeekError!void {
        return os.lseek_END(self.handle, offset);
    }

    /// Repositions read/write file offset relative to the beginning.
    /// TODO: integrate with async I/O
    pub fn seekTo(self: File, offset: u64) SeekError!void {
        return os.lseek_SET(self.handle, offset);
    }

    pub const GetPosError = os.SeekError || os.FStatError;

    /// TODO: integrate with async I/O
    pub fn getPos(self: File) GetPosError!u64 {
        return os.lseek_CUR_get(self.handle);
    }

    /// TODO: integrate with async I/O
    pub fn getEndPos(self: File) GetPosError!u64 {
        if (builtin.os.tag == .windows) {
            return windows.GetFileSizeEx(self.handle);
        }
        return (try self.stat()).size;
    }

    pub const ModeError = os.FStatError;

    /// TODO: integrate with async I/O
    pub fn mode(self: File) ModeError!Mode {
        if (builtin.os.tag == .windows) {
            return {};
        }
        return (try self.stat()).mode;
    }

    pub const Stat = struct {
        /// A number that the system uses to point to the file metadata. This number is not guaranteed to be
        /// unique across time, as some file systems may reuse an inode after it's file has been deleted.
        /// Some systems may change the inode of a file over time.
        ///
        /// On Linux, the inode _is_ structure that stores the metadata, and the inode _number_ is what
        /// you see here: the index number of the inode.
        ///
        /// The FileIndex on Windows is similar. It is a number for a file that is unique to each filesystem.
        inode: os.ino_t,

        size: u64,
        mode: Mode,

        /// access time in nanoseconds
        atime: i64,

        /// last modification time in nanoseconds
        mtime: i64,

        /// creation time in nanoseconds
        ctime: i64,
    };

    pub const StatError = os.FStatError;

    /// TODO: integrate with async I/O
    pub fn stat(self: File) StatError!Stat {
        if (builtin.os.tag == .windows) {
            var io_status_block: windows.IO_STATUS_BLOCK = undefined;
            var info: windows.FILE_ALL_INFORMATION = undefined;
            const rc = windows.ntdll.NtQueryInformationFile(self.handle, &io_status_block, &info, @sizeOf(windows.FILE_ALL_INFORMATION), .FileAllInformation);
            switch (rc) {
                .SUCCESS => {},
                .BUFFER_OVERFLOW => {},
                .INVALID_PARAMETER => unreachable,
                .ACCESS_DENIED => return error.AccessDenied,
                else => return windows.unexpectedStatus(rc),
            }
            return Stat{
                .inode = info.InternalInformation.IndexNumber,
                .size = @bitCast(u64, info.StandardInformation.EndOfFile),
                .mode = 0,
                .atime = windows.fromSysTime(info.BasicInformation.LastAccessTime),
                .mtime = windows.fromSysTime(info.BasicInformation.LastWriteTime),
                .ctime = windows.fromSysTime(info.BasicInformation.CreationTime),
            };
        }

        const st = try os.fstat(self.handle);
        const atime = st.atime();
        const mtime = st.mtime();
        const ctime = st.ctime();
        return Stat{
            .inode = st.ino,
            .size = @bitCast(u64, st.size),
            .mode = st.mode,
            .atime = @as(i64, atime.tv_sec) * std.time.ns_per_s + atime.tv_nsec,
            .mtime = @as(i64, mtime.tv_sec) * std.time.ns_per_s + mtime.tv_nsec,
            .ctime = @as(i64, ctime.tv_sec) * std.time.ns_per_s + ctime.tv_nsec,
        };
    }

    pub const UpdateTimesError = os.FutimensError || windows.SetFileTimeError;

    /// The underlying file system may have a different granularity than nanoseconds,
    /// and therefore this function cannot guarantee any precision will be stored.
    /// Further, the maximum value is limited by the system ABI. When a value is provided
    /// that exceeds this range, the value is clamped to the maximum.
    /// TODO: integrate with async I/O
    pub fn updateTimes(
        self: File,
        /// access timestamp in nanoseconds
        atime: i64,
        /// last modification timestamp in nanoseconds
        mtime: i64,
    ) UpdateTimesError!void {
        if (builtin.os.tag == .windows) {
            const atime_ft = windows.nanoSecondsToFileTime(atime);
            const mtime_ft = windows.nanoSecondsToFileTime(mtime);
            return windows.SetFileTime(self.handle, null, &atime_ft, &mtime_ft);
        }
        const times = [2]os.timespec{
            os.timespec{
                .tv_sec = math.cast(isize, @divFloor(atime, std.time.ns_per_s)) catch maxInt(isize),
                .tv_nsec = math.cast(isize, @mod(atime, std.time.ns_per_s)) catch maxInt(isize),
            },
            os.timespec{
                .tv_sec = math.cast(isize, @divFloor(mtime, std.time.ns_per_s)) catch maxInt(isize),
                .tv_nsec = math.cast(isize, @mod(mtime, std.time.ns_per_s)) catch maxInt(isize),
            },
        };
        try os.futimens(self.handle, &times);
    }

    pub const ReadError = os.ReadError;
    pub const PReadError = os.PReadError;

    pub fn read(self: File, buffer: []u8) ReadError!usize {
        if (need_async_thread and self.io_mode == .blocking and !self.async_block_allowed) {
            return std.event.Loop.instance.?.read(self.handle, buffer);
        } else {
            return os.read(self.handle, buffer);
        }
    }

    /// Returns the number of bytes read. If the number read is smaller than `buffer.len`, it
    /// means the file reached the end. Reaching the end of a file is not an error condition.
    pub fn readAll(self: File, buffer: []u8) ReadError!usize {
        var index: usize = 0;
        while (index != buffer.len) {
            const amt = try self.read(buffer[index..]);
            if (amt == 0) break;
            index += amt;
        }
        return index;
    }

    pub fn pread(self: File, buffer: []u8, offset: u64) PReadError!usize {
        if (need_async_thread and self.io_mode == .blocking and !self.async_block_allowed) {
            return std.event.Loop.instance.?.pread(self.handle, buffer, offset);
        } else {
            return os.pread(self.handle, buffer, offset);
        }
    }

    /// Returns the number of bytes read. If the number read is smaller than `buffer.len`, it
    /// means the file reached the end. Reaching the end of a file is not an error condition.
    pub fn preadAll(self: File, buffer: []u8, offset: u64) PReadError!usize {
        var index: usize = 0;
        while (index != buffer.len) {
            const amt = try self.pread(buffer[index..], offset + index);
            if (amt == 0) break;
            index += amt;
        }
        return index;
    }

    pub fn readv(self: File, iovecs: []const os.iovec) ReadError!usize {
        if (need_async_thread and self.io_mode == .blocking and !self.async_block_allowed) {
            return std.event.Loop.instance.?.readv(self.handle, iovecs);
        } else {
            return os.readv(self.handle, iovecs);
        }
    }

    /// Returns the number of bytes read. If the number read is smaller than the total bytes
    /// from all the buffers, it means the file reached the end. Reaching the end of a file
    /// is not an error condition.
    /// The `iovecs` parameter is mutable because this function needs to mutate the fields in
    /// order to handle partial reads from the underlying OS layer.
    pub fn readvAll(self: File, iovecs: []os.iovec) ReadError!usize {
        if (iovecs.len == 0) return;

        var i: usize = 0;
        var off: usize = 0;
        while (true) {
            var amt = try self.readv(iovecs[i..]);
            var eof = amt == 0;
            off += amt;
            while (amt >= iovecs[i].iov_len) {
                amt -= iovecs[i].iov_len;
                i += 1;
                if (i >= iovecs.len) return off;
                eof = false;
            }
            if (eof) return off;
            iovecs[i].iov_base += amt;
            iovecs[i].iov_len -= amt;
        }
    }

    pub fn preadv(self: File, iovecs: []const os.iovec, offset: u64) PReadError!usize {
        if (need_async_thread and self.io_mode == .blocking and !self.async_block_allowed) {
            return std.event.Loop.instance.?.preadv(self.handle, iovecs, offset);
        } else {
            return os.preadv(self.handle, iovecs, offset);
        }
    }

    /// Returns the number of bytes read. If the number read is smaller than the total bytes
    /// from all the buffers, it means the file reached the end. Reaching the end of a file
    /// is not an error condition.
    /// The `iovecs` parameter is mutable because this function needs to mutate the fields in
    /// order to handle partial reads from the underlying OS layer.
    pub fn preadvAll(self: File, iovecs: []const os.iovec, offset: u64) PReadError!void {
        if (iovecs.len == 0) return;

        var i: usize = 0;
        var off: usize = 0;
        while (true) {
            var amt = try self.preadv(iovecs[i..], offset + off);
            var eof = amt == 0;
            off += amt;
            while (amt >= iovecs[i].iov_len) {
                amt -= iovecs[i].iov_len;
                i += 1;
                if (i >= iovecs.len) return off;
                eof = false;
            }
            if (eof) return off;
            iovecs[i].iov_base += amt;
            iovecs[i].iov_len -= amt;
        }
    }

    pub const WriteError = os.WriteError;
    pub const PWriteError = os.PWriteError;

    pub fn write(self: File, bytes: []const u8) WriteError!usize {
        if (need_async_thread and self.io_mode == .blocking and !self.async_block_allowed) {
            return std.event.Loop.instance.?.write(self.handle, bytes);
        } else {
            return os.write(self.handle, bytes);
        }
    }

    pub fn writeAll(self: File, bytes: []const u8) WriteError!void {
        var index: usize = 0;
        while (index < bytes.len) {
            index += try self.write(bytes[index..]);
        }
    }

    pub fn pwrite(self: File, bytes: []const u8, offset: u64) PWriteError!usize {
        if (need_async_thread and self.io_mode == .blocking and !self.async_block_allowed) {
            return std.event.Loop.instance.?.pwrite(self.handle, bytes, offset);
        } else {
            return os.pwrite(self.handle, bytes, offset);
        }
    }

    pub fn pwriteAll(self: File, bytes: []const u8, offset: u64) PWriteError!void {
        var index: usize = 0;
        while (index < bytes.len) {
            index += try self.pwrite(bytes[index..], offset + index);
        }
    }

    pub fn writev(self: File, iovecs: []const os.iovec_const) WriteError!usize {
        if (need_async_thread and self.io_mode == .blocking and !self.async_block_allowed) {
            return std.event.Loop.instance.?.writev(self.handle, iovecs);
        } else {
            return os.writev(self.handle, iovecs);
        }
    }

    /// The `iovecs` parameter is mutable because this function needs to mutate the fields in
    /// order to handle partial writes from the underlying OS layer.
    pub fn writevAll(self: File, iovecs: []os.iovec_const) WriteError!void {
        if (iovecs.len == 0) return;

        var i: usize = 0;
        while (true) {
            var amt = try self.writev(iovecs[i..]);
            while (amt >= iovecs[i].iov_len) {
                amt -= iovecs[i].iov_len;
                i += 1;
                if (i >= iovecs.len) return;
            }
            iovecs[i].iov_base += amt;
            iovecs[i].iov_len -= amt;
        }
    }

    pub fn pwritev(self: File, iovecs: []os.iovec_const, offset: usize) PWriteError!usize {
        if (need_async_thread and self.io_mode == .blocking and !self.async_block_allowed) {
            return std.event.Loop.instance.?.pwritev(self.handle, iovecs, offset);
        } else {
            return os.pwritev(self.handle, iovecs, offset);
        }
    }

    /// The `iovecs` parameter is mutable because this function needs to mutate the fields in
    /// order to handle partial writes from the underlying OS layer.
    pub fn pwritevAll(self: File, iovecs: []os.iovec_const, offset: usize) PWriteError!void {
        if (iovecs.len == 0) return;

        var i: usize = 0;
        var off: usize = 0;
        while (true) {
            var amt = try self.pwritev(iovecs[i..], offset + off);
            off += amt;
            while (amt >= iovecs[i].iov_len) {
                amt -= iovecs[i].iov_len;
                i += 1;
                if (i >= iovecs.len) return;
            }
            iovecs[i].iov_base += amt;
            iovecs[i].iov_len -= amt;
        }
    }

    pub const WriteFileOptions = struct {
        in_offset: u64 = 0,

        /// `null` means the entire file. `0` means no bytes from the file.
        /// When this is `null`, trailers must be sent in a separate writev() call
        /// due to a flaw in the BSD sendfile API. Other operating systems, such as
        /// Linux, already do this anyway due to API limitations.
        /// If the size of the source file is known, passing the size here will save one syscall.
        in_len: ?u64 = null,

        headers_and_trailers: []os.iovec_const = &[0]os.iovec_const{},

        /// The trailer count is inferred from `headers_and_trailers.len - header_count`
        header_count: usize = 0,
    };

    pub const WriteFileError = os.SendFileError;

    /// TODO integrate with async I/O
    pub fn writeFileAll(self: File, in_file: File, args: WriteFileOptions) WriteFileError!void {
        const count = blk: {
            if (args.in_len) |l| {
                if (l == 0) {
                    return self.writevAll(args.headers_and_trailers);
                } else {
                    break :blk l;
                }
            } else {
                break :blk 0;
            }
        };
        const headers = args.headers_and_trailers[0..args.header_count];
        const trailers = args.headers_and_trailers[args.header_count..];
        const zero_iovec = &[0]os.iovec_const{};
        // When reading the whole file, we cannot put the trailers in the sendfile() syscall,
        // because we have no way to determine whether a partial write is past the end of the file or not.
        const trls = if (count == 0) zero_iovec else trailers;
        const offset = args.in_offset;
        const out_fd = self.handle;
        const in_fd = in_file.handle;
        const flags = 0;
        var amt: usize = 0;
        hdrs: {
            var i: usize = 0;
            while (i < headers.len) {
                amt = try os.sendfile(out_fd, in_fd, offset, count, headers[i..], trls, flags);
                while (amt >= headers[i].iov_len) {
                    amt -= headers[i].iov_len;
                    i += 1;
                    if (i >= headers.len) break :hdrs;
                }
                headers[i].iov_base += amt;
                headers[i].iov_len -= amt;
            }
        }
        if (count == 0) {
            var off: u64 = amt;
            while (true) {
                amt = try os.sendfile(out_fd, in_fd, offset + off, 0, zero_iovec, zero_iovec, flags);
                if (amt == 0) break;
                off += amt;
            }
        } else {
            var off: u64 = amt;
            while (off < count) {
                amt = try os.sendfile(out_fd, in_fd, offset + off, count - off, zero_iovec, trailers, flags);
                off += amt;
            }
            amt = @intCast(usize, off - count);
        }
        var i: usize = 0;
        while (i < trailers.len) {
            while (amt >= headers[i].iov_len) {
                amt -= trailers[i].iov_len;
                i += 1;
                if (i >= trailers.len) return;
            }
            trailers[i].iov_base += amt;
            trailers[i].iov_len -= amt;
            amt = try os.writev(self.handle, trailers[i..]);
        }
    }

    pub const InStream = io.InStream(File, ReadError, read);

    pub fn inStream(file: File) io.InStream(File, ReadError, read) {
        return .{ .context = file };
    }

    pub const OutStream = io.OutStream(File, WriteError, write);

    pub fn outStream(file: File) OutStream {
        return .{ .context = file };
    }

    pub const SeekableStream = io.SeekableStream(
        File,
        SeekError,
        GetPosError,
        seekTo,
        seekBy,
        getPos,
        getEndPos,
    );

    pub fn seekableStream(file: File) SeekableStream {
        return .{ .context = file };
    }
};
