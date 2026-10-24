<?php

/**
 * The ReflectionFunction class reports
 * information about a function.
 */
class ReflectionFunction extends ReflectionFunctionAbstract
{
    /**
     * @var string Function name, same as calling the ReflectionFunction::getName() method
     */
    public string $name;

    /**
     * Indicates deprecated functions.
     */
    public const IS_DEPRECATED = 2048;

    /**
     * Constructs a ReflectionFunction object
     * @param string|Closure $function The name of the function to reflect or a closure.
     * @throws ReflectionException if the function does not exist.
     */
    public function __construct(Closure|string $function) {}

    /**
     * Returns the string representation of the ReflectionFunction object.
     */
    public function __toString(): string {}

    /**
     * Exports function
     * @param string $name The reflection to export.
     * @param bool $return Setting to true will return the export, as opposed to emitting it. Setting to false (the default) will do the opposite.
     * @return string|null If the $return parameter is set to true, then the export is returned as a string, otherwise null is returned.
     * @removed 8.0
     * @deprecated
     */
    public static function export($name, $return = false) {}

    /**
     * Checks if function is disabled
     * @return bool true if it's disable, otherwise false
     * @deprecated
     */
    public function isDisabled(): bool {}

    /**
     * Invokes function
     * @param mixed ...$args [optional] The passed in argument list. It accepts a variable number of arguments which are passed to the function much like call_user_func is.
     * @return mixed Returns the result of the invoked function call.
     */
    public function invoke(mixed ...$args): mixed {}

    /**
     * Invokes function args
     * @param array $args The passed arguments to the function as an array, much like call_user_func_array works.
     * @return mixed the result of the invoked function
     */
    public function invokeArgs(array $args): mixed {}

    /**
     * Returns a dynamically created closure for the function
     * @return Closure Returns a Closure. Prior to PHP 8.1, null was returned in case of an error.
     */
    public function getClosure(): Closure {}

    /**
     * Checks if a function is anonymous
     * @return bool Returns true if the function is anonymous, otherwise false.
     */
    public function isAnonymous(): bool {}
}
