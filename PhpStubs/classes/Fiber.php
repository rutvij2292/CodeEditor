<?php

/**
 * Fibers represent full-stack, interruptible functions. Fibers may be suspended from anywhere in
 * the call-stack, pausing execution within the fiber until the fiber is resumed at a later time.
 * @since 8.1
 * @template TStart
 * @template TResume
 * @template TReturn
 * @template TSuspend
 */
final class Fiber
{
    /**
     * Creates a new Fiber instance
     * @param callable $callback Function to invoke when starting the fiber.
     */
    public function __construct(callable $callback) {}

    /**
     * Starts execution of the fiber. Returns when the fiber suspends or terminates.
     * @param TStart ...$args Arguments passed to fiber function.
     * @return TSuspend|null Value from the first suspension point or NULL if the fiber returns.
     * @throws FiberError If the fiber has already been started.
     * @throws Throwable If the fiber callable throws an uncaught exception.
     */
    public function start(mixed ...$args): mixed {}

    /**
     * Resumes the fiber, returning the given value from Fiber::suspend().
     * Returns when the fiber suspends or terminates.
     * @param TResume $value The value to resume the fiber. This value will be the return value of the current Fiber::suspend call.
     * @return TSuspend|null Value from the next suspension point or NULL if the fiber returns.
     * @throws FiberError If the fiber has not started, is running, or has terminated.
     * @throws Throwable If the fiber callable throws an uncaught exception.
     */
    public function resume(mixed $value = null): mixed {}

    /**
     * Throws the given exception into the fiber from Fiber::suspend().
     * Returns when the fiber suspends or terminates.
     * @param Throwable $exception The exception to throw into the fiber from the current Fiber::suspend call.
     * @return TSuspend|null Value from the next suspension point or NULL if the fiber returns.
     * @throws FiberError If the fiber has not started, is running, or has terminated.
     * @throws Throwable If the fiber callable throws an uncaught exception.
     */
    public function throw(Throwable $exception): mixed {}

    /**
     * Determines if the fiber has started
     * @return bool True if the fiber has been started.
     */
    public function isStarted(): bool {}

    /**
     * Determines if the fiber is suspended
     * @return bool True if the fiber is suspended.
     */
    public function isSuspended(): bool {}

    /**
     * Determines if the fiber is running
     * @return bool True if the fiber is currently running.
     */
    public function isRunning(): bool {}

    /**
     * Determines if the fiber has terminated
     * @return bool True if the fiber has completed execution (returned or threw).
     */
    public function isTerminated(): bool {}

    /**
     * Gets the value returned by the Fiber
     * @return TReturn Return value of the fiber callback. NULL is returned if the fiber does not have a return statement.
     * @throws FiberError If the fiber has not terminated or the fiber threw an exception.
     */
    public function getReturn(): mixed {}

    /**
     * Gets the currently executing Fiber instance
     * @return Fiber|null Returns the currently executing fiber instance or NULL if in {main}.
     */
    public static function getCurrent(): ?Fiber {}

    /**
     * Suspend execution of the fiber. The fiber may be resumed with Fiber::resume() or Fiber::throw().
     *
     * Cannot be called from {main}.
     * @param TSuspend $value Value to return from Fiber::resume() or Fiber::throw().
     * @return TResume Value provided to Fiber::resume().
     * @throws FiberError Thrown if not within a fiber (i.e., if called from {main}).
     * @throws Throwable Exception provided to Fiber::throw().
     */
    public static function suspend(mixed $value = null): mixed {}
}
