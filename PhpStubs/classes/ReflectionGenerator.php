<?php

/**
 * The ReflectionGenerator class reports information about a generator.
 * @since 7.0
 */
final class ReflectionGenerator
{
    /**
     * Constructs a ReflectionGenerator object
     * @param Generator $generator A generator object.
     * @since 7.0
     */
    public function __construct(Generator $generator) {}

    /**
     * Gets the currently executing line of the generator
     * @return int Returns the line number of the currently executing statement in the generator.
     * @since 7.0
     */
    public function getExecutingLine(): int {}

    /**
     * Gets the file name of the currently executing generator
     * @return string Returns the full path and file name of the currently executing generator.
     * @since 7.0
     */
    public function getExecutingFile(): string {}

    /**
     * Gets the trace of the executing generator
     * @param int $options The value of options can be any of the following the following flags. Available options: DEBUG_BACKTRACE_PROVIDE_OBJECT - Default DEBUG_BACKTRACE_IGNORE_ARGS - Don't include the argument information for functions in the stack trace.
     * @return array Returns the trace of the currently executing generator.
     * @since 7.0
     */
    public function getTrace(int $options = DEBUG_BACKTRACE_PROVIDE_OBJECT): array {}

    /**
     * Gets the function name of the generator
     * @return ReflectionFunctionAbstract Returns a ReflectionFunctionAbstract class. This will be ReflectionFunction for functions, or ReflectionMethod for methods.
     * @since 7.0
     */
    public function getFunction(): ReflectionFunctionAbstract {}

    /**
     * Gets the function name of the generator
     * @return object|null Returns the $this value, or null if the generator was not created in a class context.
     * @since 7.0
     */
    public function getThis(): ?object {}

    /**
     * Gets the executing Generator object
     * @return Generator Returns the currently executing Generator object.
     * @since 7.0
     */
    public function getExecutingGenerator(): Generator {}

    /**
     * Checks if execution finished
     *
     * Returns whether the execution reached the end of the function, a return statement or if an
     * exception was thrown.
     * @since 8.4
     */
    public function isClosed(): bool {}
}
