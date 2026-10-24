<?php

/**
 * Check whether the file exists.
 */
const POSIX_F_OK = 0;

/**
 * Check whether the file exists and has execute permissions.
 */
const POSIX_X_OK = 1;

/**
 * Check whether the file exists and has write permissions.
 */
const POSIX_W_OK = 2;

/**
 * Check whether the file exists and has read permissions.
 */
const POSIX_R_OK = 4;

/**
 * Normal file
 */
const POSIX_S_IFREG = 32768;

/**
 * Character special file
 */
const POSIX_S_IFCHR = 8192;

/**
 * Block special file
 */
const POSIX_S_IFBLK = 24576;

/**
 * FIFO (named pipe) special file
 */
const POSIX_S_IFIFO = 4096;

/**
 * Socket
 */
const POSIX_S_IFSOCK = 49152;

/**
 * The maximum size of the process's address space in bytes. See also PHP's memory_limit configuration directive.
 */
const POSIX_RLIMIT_AS = 5;

/**
 * The maximum size of a core file. If the limit is set to 0, no core file will be generated.
 */
const POSIX_RLIMIT_CORE = 4;

/**
 * The maximum amount of CPU time that the process can use, in seconds.
 * When the soft limit is hit, a SIGXCPU signal will be sent, which can be caught with pcntl_signal().
 * Depending on the operating system, additional SIGXCPU signals may be sent each second until the hard limit is hit,
 * at which point an uncatchable SIGKILL signal is sent. See also set_time_limit().
 */
const POSIX_RLIMIT_CPU = 0;

/**
 * The maximum size of the process's data segment, in bytes.
 * It is extremely unlikely that this will have any effect on
 * the execution of PHP unless an extension is in use that calls brk() or sbrk().
 */
const POSIX_RLIMIT_DATA = 2;

/**
 * The maximum size of files that the process can create, in bytes.
 */
const POSIX_RLIMIT_FSIZE = 1;

/**
 * The maximum number of locks that the process can create.
 * This is only supported on extremely old Linux kernels.
 */
const POSIX_RLIMIT_LOCKS = 10;

/**
 * The maximum number of bytes that can be allocated for POSIX message queues.
 * PHP does not ship with support for POSIX message queues,
 * so this limit will not have any effect unless you are using an extension that implements that support.
 */
const POSIX_RLIMIT_MSGQUEUE = 12;

/**
 * The maximum value to which the process can be  reniced to. The value that will be used will be 20 - limit, as resource limit values cannot be negative.
 */
const POSIX_RLIMIT_NICE = 13;

/**
 * The maximum real time priority that can be set via the sched_setscheduler() and sched_setparam() system calls.
 */
const POSIX_RLIMIT_RTPRIO = 14;

/**
 * The maximum amount of CPU time, in microseconds,
 * that the process can consume without making a blocking system call if it is using real time scheduling.
 */
const POSIX_RLIMIT_RTTIME = 15;

/**
 * The maximum number of signals that can be queued for the real user ID of the process.
 */
const POSIX_RLIMIT_SIGPENDING = 11;

/**
 * The maximum number of bytes that can be locked into memory.
 */
const POSIX_RLIMIT_MEMLOCK = 6;

/**
 * A value one greater than the maximum file descriptor number that can be opened by this process.
 */
const POSIX_RLIMIT_NOFILE = 8;

/**
 * The maximum number of processes (and/or threads, on some operating systems)
 * that can be created for the real user ID of the process.
 */
const POSIX_RLIMIT_NPROC = 7;

/**
 * The maximum size of the process's resident set, in pages.
 */
const POSIX_RLIMIT_RSS = 5;

/**
 * The maximum size of the process stack, in bytes.
 */
const POSIX_RLIMIT_STACK = 3;

/**
 * Used to indicate an infinite value for a resource limit.
 */
const POSIX_RLIMIT_INFINITY = 9223372036854775807;

const POSIX_SC_ARG_MAX = 0;

const POSIX_SC_PAGESIZE = 30;

const POSIX_SC_NPROCESSORS_CONF = 83;

const POSIX_SC_NPROCESSORS_ONLN = 84;

const POSIX_PC_LINK_MAX = 0;

const POSIX_PC_MAX_CANON = 1;

const POSIX_PC_MAX_INPUT = 2;

const POSIX_PC_NAME_MAX = 3;

const POSIX_PC_PATH_MAX = 4;

const POSIX_PC_PIPE_BUF = 5;

const POSIX_PC_CHOWN_RESTRICTED = 6;

const POSIX_PC_NO_TRUNC = 7;

const POSIX_PC_ALLOC_SIZE_MIN = 18;

const POSIX_PC_SYMLINK_MAX = 19;

const POSIX_SC_OPEN_MAX = 4;

/**
 * @since 8.4
 */
const POSIX_SC_CHILD_MAX = 1;

/**
 * @since 8.4
 */
const POSIX_SC_CLK_TCK = 2;
