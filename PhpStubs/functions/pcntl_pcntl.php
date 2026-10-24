<?php

/**
 * Forks the currently running process
 * @return int On success, the PID of the child process is returned in the parent's thread of execution, and a 0 is returned in the child's thread of execution. On failure, a -1 will be returned in the parent's context, no child process will be created, and a PHP error is raised.
 */
function pcntl_fork(): int {}

/**
 * Waits on or returns the status of a forked child
 * @param int $process_id The value of pid can be one of the following: possible values for pid < -1 wait for any child process whose process group ID is equal to the absolute value of pid. -1 wait for any child process; this is the same behaviour that the wait function exhibits. 0 wait for any child ...
 * @param int &$status pcntl_waitpid will store status information in the status parameter which can be evaluated using the following functions: pcntl_wifexited, pcntl_wifstopped, pcntl_wifsignaled, pcntl_wexitstatus, pcntl_wtermsig and pcntl_wstopsig.
 * @param int $flags [optional] The value of options is the value of zero or more of the following two global constants OR'ed together: possible values for options WNOHANG return immediately if no child has exited. WUNTRACED return for children which are stopped, and whose status has not been reported.
 * @param array &$resource_usage
 * @return int pcntl_waitpid returns the process ID of the child which exited, -1 on error or zero if WNOHANG was used and no child was available
 */
function pcntl_waitpid(
    int $process_id,
    &$status,
    int $flags = 0,
    &$resource_usage = []
): int {}

/**
 * Waits on or returns the status of a forked child
 * @param int &$status pcntl_wait will store status information in the status parameter which can be evaluated using the following functions: pcntl_wifexited, pcntl_wifstopped, pcntl_wifsignaled, pcntl_wexitstatus, pcntl_wtermsig and pcntl_wstopsig.
 * @param int $flags [optional] If wait3 is available on your system (mostly BSD-style systems), you can provide the optional flags parameter. If this parameter is not provided, wait will be used for the system call. If wait3 is not available, providing a value for flags will have no effect. The value ...
 * @param array &$resource_usage
 * @return int pcntl_wait returns the process ID of the child which exited, -1 on error or zero if WNOHANG was provided as an option (on wait3-available systems) and no child was available.
 */
function pcntl_wait(
    &$status,
    int $flags = 0,
    &$resource_usage
= []
): int {}

/**
 * Installs a signal handler
 * @param int $signal The signal number.
 * @param callable|int $handler The signal handler. This may be either a callable, which will be invoked to handle the signal, or either of the two global constants SIG_IGN or SIG_DFL, which will ignore the signal or restore the default signal handler respectively. If a callable is given, it must ...
 * @param bool $restart_syscalls [optional] Specifies whether system call restarting should be used when this signal arrives.
 * @return bool TRUE on success or FALSE on failure.
 */
function pcntl_signal(
    int $signal,
    $handler,
    bool $restart_syscalls = true
): bool {}

/**
 * Calls signal handlers for pending signals
 * @return bool TRUE on success or FALSE on failure.
 */
function pcntl_signal_dispatch(): bool {}

/**
 * Checks if status code represents a normal exit
 * @param int $status The status parameter is the status parameter supplied to a successful call to pcntl_waitpid.
 * @return bool TRUE if the child status code represents a normal exit, FALSE otherwise.
 */
function pcntl_wifexited(int $status): bool {}

/**
 * Checks whether the child process is currently stopped
 * @param int $status The status parameter is the status parameter supplied to a successful call to pcntl_waitpid.
 * @return bool TRUE if the child process which caused the return is currently stopped, FALSE otherwise.
 */
function pcntl_wifstopped(int $status): bool {}

/**
 * Checks whether the status code represents a termination due to a signal
 * @param int $status The status parameter is the status parameter supplied to a successful call to pcntl_waitpid.
 * @return bool TRUE if the child process exited because of a signal which was not caught, FALSE otherwise.
 */
function pcntl_wifsignaled(int $status): bool {}

/**
 * Returns the return code of a terminated child
 * @param int $status The status parameter is the status parameter supplied to a successful call to pcntl_waitpid.
 * @return int|false the return code, as an integer.
 */
function pcntl_wexitstatus(int $status): int|false {}

/**
 * Checks whether the child process has continued from a job control stop
 *
 * Checks whether the child process which caused the return of pcntl_waitpid has continued from a
 * job control stop. This function is only useful if the call to pcntl_waitpid was done using the
 * WCONTINUED option.
 * @param int $status The status parameter is the status parameter supplied to a successful call to pcntl_waitpid.
 * @return bool Returns true if the child process which caused the return of pcntl_waitpid has continued from a job control stop, false otherwise.
 */
function pcntl_wifcontinued(int $status): bool {}

/**
 * Returns the signal which caused the child to terminate
 * @param int $status The status parameter is the status parameter supplied to a successful call to pcntl_waitpid.
 * @return int|false the signal number, as an integer.
 */
function pcntl_wtermsig(int $status): int|false {}

/**
 * Returns the signal which caused the child to stop
 * @param int $status The status parameter is the status parameter supplied to a successful call to pcntl_waitpid.
 * @return int|false the signal number.
 */
function pcntl_wstopsig(int $status): int|false {}

/**
 * Executes specified program in current process space
 * @param string $path path must be the path to a binary executable or a script with a valid path pointing to an executable in the shebang ( #!/usr/local/bin/perl for example) as the first line. See your system's man execve(2) page for additional information.
 * @param array $args args is an array of argument strings passed to the program.
 * @param array $env_vars envs is an array of strings which are passed as environment to the program. The array is in the format of name => value, the key being the name of the environmental variable and the value being the value of that variable.
 * @return bool FALSE on error and does not return on success.
 */
function pcntl_exec(string $path, array $args = [], array $env_vars = []): bool {}

/**
 * Set an alarm clock for delivery of a signal
 * @param int $seconds The number of seconds to wait. If seconds is zero, no new alarm is created.
 * @return int the time in seconds that any previously scheduled alarm had remaining before it was to be delivered, or 0 if there was no previously scheduled alarm.
 */
function pcntl_alarm(int $seconds): int {}

/**
 * Retrieve the error number set by the last pcntl function which failed
 * @return int error code.
 * @since 5.3
 */
function pcntl_get_last_error(): int {}

/**
 * Alias of pcntl_get_last_error
 * @return int error code.
 * @since 5.3
 */
function pcntl_errno(): int {}

/**
 * Retrieve the system error message associated with the given errno
 * @param int $error_code
 * @return string|false error description on success or FALSE on failure.
 * @since 5.3
 */
function pcntl_strerror(int $error_code): string {}

/**
 * Get the priority of any process
 * @param int|null $process_id [optional] If not specified, the pid of the current process  (getmypid()) is used.
 * @param int $mode [optional] One of PRIO_PGRP, PRIO_USER or PRIO_PROCESS.
 * @return int|false pcntl_getpriority returns the priority of the process or FALSE on error. A lower numerical value causes more favorable scheduling.
 */
function pcntl_getpriority(?int $process_id = null, int $mode = PRIO_PROCESS): int|false {}

/**
 * Change the priority of any process
 * @param int $priority priority is generally a value in the range -20 to 20. The default priority is 0 while a lower numerical value causes more favorable scheduling. Because priority levels can differ between system types and kernel versions, please see your system's setpriority(2) man page for ...
 * @param int|null $process_id [optional] If not specified, the pid of the current process (getmypid()) is used.
 * @param int $mode [optional] One of PRIO_PGRP, PRIO_USER or PRIO_PROCESS.
 * @return bool TRUE on success or FALSE on failure.
 */
function pcntl_setpriority(int $priority, ?int $process_id = null, int $mode = PRIO_PROCESS): bool {}

/**
 * Sets and retrieves blocked signals
 * @param int $mode Sets the behavior of pcntl_sigprocmask. Possible values: SIG_BLOCK: Add the signals to the currently blocked signals. SIG_UNBLOCK: Remove the signals from the currently blocked signals. SIG_SETMASK: Replace the currently blocked signals by the given list of signals.
 * @param array $signals List of signals.
 * @param array &$old_signals [optional] The old_signals parameter is set to an array containing the list of the previously blocked signals.
 * @return bool TRUE on success or FALSE on failure.
 */
function pcntl_sigprocmask(int $mode, array $signals, &$old_signals = null): bool {}

/**
 * Waits for signals
 * @param array $signals Array of signals to wait for.
 * @param array &$info The info parameter is set to an array containing informations about the signal. The following elements are set for all signals: signo: Signal number errno: An error number code: Signal code The following elements may be set for the SIGCHLD signal: status: Exit value or signal ...
 * @return int|false On success, pcntl_sigwaitinfo returns a signal number.
 */
function pcntl_sigwaitinfo(array $signals, &$info = []): int|false {}

/**
 * Waits for signals, with a timeout
 * @param array $signals Array of signals to wait for.
 * @param array &$info The siginfo is set to an array containing informations about the signal. See pcntl_sigwaitinfo.
 * @param int $seconds [optional] Timeout in seconds.
 * @param int $nanoseconds [optional] Timeout in nanoseconds.
 * @return int|false On success, pcntl_sigtimedwait returns a signal number.
 */
function pcntl_sigtimedwait(array $signals, &$info = [], int $seconds = 0, int $nanoseconds = 0): int|false {}

/**
 * Enable/disable asynchronous signal handling or return the old setting.
 *
 * If the enable parameter is omitted, it returns whether asynchronous
 * signal handling is enabled.
 * @param bool|null $enable Whether asynchronous signal handling should be enabled.
 * @return bool When used as getter (enable parameter is null) it returns whether asynchronous signal handling is enabled. When used as setter (enable parameter is not null), it returns whether asynchronous signal handling was enabled before the function call.
 * @since 7.1
 */
function pcntl_async_signals(
    ?bool $enable = null
): bool {}

/**
 * Get the current handler for specified signal.
 * @param int $signal The signal number.
 * @return bool|resource This function may return an integer value that refers to SIG_DFL or SIG_IGN. If a custom handler has been set, that callable is returned.
 * @since 7.1
 */
function pcntl_signal_get_handler(int $signal) {}

/**
 * Dissociates parts of the process execution context
 *
 * pcntl_unshare allows a process to disassociate parts of its execution context that are currently
 * being shared with other processes. The main use of pcntl_unshare is to allow a process to control
 * its shared execution context without creating a new process.
 * @param int $flags The flags parameter is a bitmask that specifies which parts of the execution context should be unshared. This parameter is specified by ORing together zero or more of the CLONE_* constants: CLONE_NEWNS CLONE_NEWIPC CLONE_NEWUTS CLONE_NEWNET CLONE_NEWPID CLONE_NEWUSER ...
 * @return bool Returns 0 on success, -1 otherwise. On failure it sets an error code, that can be retrieved with pcntl_get_last_error.
 * @since 7.4
 */
function pcntl_unshare(int $flags): bool {}

/**
 * Waits for a child process to change state
 *
 * Obtains status information pertaining to termination, stop, and/or continue events in one of the
 * caller's child processes.
 * @since 8.4
 */
function pcntl_waitid(int $idtype = P_ALL, ?int $id = null, &$info = [], int $flags = WEXITED): bool {}

/**
 * Get the cpu affinity of a process
 *
 * Retrieve the cpu affinity of the process_id.
 * @since 8.4
 * @throws \ValueError A ValueError is thrown when process_id is an invalid process id or the cpu mask had failed to be created. If process_id is a process for which the current user has no allowed permission, a E_WARNING is emitted.
 */
function pcntl_getcpuaffinity(?int $process_id = null): array|false {}

/**
 * Set the cpu affinity of a process
 *
 * Sets the cpu affinity for the process_id with the cpu affinity mask given by cpu_ids.
 * @since 8.4
 * @throws \TypeError A TypeError is thrown if one of the cpu id from the cpu_ids is invalid.
 * @throws \ValueError A ValueError is thrown if process_id is an invalid process id or the cpu mask had failed to be created.
 */
function pcntl_setcpuaffinity(?int $process_id = null, array $cpu_ids = []): bool {}

/**
 * Get the CPU number on which the calling process last executed
 *
 * pcntl_getcpu returns the number of the CPU on which the calling process was last executed. This
 * function uses the sched_getcpu(3) system call available on Linux.
 * @since 8.4
 */
function pcntl_getcpu(): int {}
