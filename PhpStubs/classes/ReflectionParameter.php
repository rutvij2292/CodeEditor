<?php

/**
 * The ReflectionParameter class retrieves
 * information about function's or method's parameters.
 */
class ReflectionParameter implements Reflector
{
    /**
     * @var string Name of the parameter, same as calling the ReflectionParameter::getName() method
     */
    public string $name;

    /**
     * Construct
     * @param callable $function The function to reflect parameters from.
     * @param string|int $param Either an integer specifying the position of the parameter (starting with zero), or a the parameter name as string.
     * @throws ReflectionException if the function or parameter does not exist.
     */
    public function __construct($function, string|int $param) {}

    /**
     * Exports
     * @param string $function The function name.
     * @param string $parameter The parameter name.
     * @param bool $return Setting to true will return the export, as opposed to emitting it. Setting to false (the default) will do the opposite.
     * @return string|null The exported reflection.
     * @removed 8.0
     * @deprecated
     */
    public static function export($function, $parameter, $return = false) {}

    /**
     * Returns the string representation of the ReflectionParameter object.
     * @return string The string.
     */
    public function __toString(): string {}

    /**
     * Gets parameter name
     * @return string The name of the reflected parameter.
     */
    public function getName(): string {}

    /**
     * Checks if passed by reference
     * @return bool true if the parameter is passed in by reference, otherwise false
     */
    public function isPassedByReference(): bool {}

    /**
     * Returns whether this parameter can be passed by value
     * @return bool true if the parameter can be passed by value, false otherwise. Prior to PHP 8.1, null was returned in case of an error.
     * @since 5.4
     */
    public function canBePassedByValue(): bool {}

    /**
     * Gets declaring function
     * @return ReflectionFunctionAbstract A ReflectionFunctionAbstract object.
     * @since 5.2
     */
    public function getDeclaringFunction(): ReflectionFunctionAbstract {}

    /**
     * Gets declaring class
     * @return ReflectionClass|null A ReflectionClass object or null if called on function.
     */
    public function getDeclaringClass(): ?ReflectionClass {}

    /**
     * Gets the class type hinted for the parameter as a ReflectionClass object.
     * @return ReflectionClass|null A ReflectionClass object.
     * @see ReflectionParameter::getType()
     * @deprecated Use ReflectionParameter::getType() and the ReflectionType APIs should be used instead.
     */
    public function getClass(): ?ReflectionClass {}

    /**
     * Checks if the parameter has a type associated with it.
     * @return bool true if a type is specified, false otherwise.
     * @since 7.0
     */
    public function hasType(): bool {}

    /**
     * Gets a parameter's type
     * @return ReflectionType|null Returns a ReflectionType object if a parameter type is specified, null otherwise.
     * @since 7.0
     */
    public function getType(): ?ReflectionType {}

    /**
     * Checks if parameter expects an array
     * @return bool true if an array is expected, false otherwise.
     * @see ReflectionParameter::getType()
     * @deprecated Use ReflectionParameter::getType() and the ReflectionType APIs should be used instead.
     */
    public function isArray(): bool {}

    /**
     * Returns whether parameter MUST be callable
     * @return bool Returns true if the parameter is callable, false if it is not. Prior to PHP 8.1, null was returned on failure.
     * @since 5.4
     * @see ReflectionParameter::getType()
     * @deprecated Use ReflectionParameter::getType() and the ReflectionType APIs should be used instead.
     */
    public function isCallable(): bool {}

    /**
     * Checks if null is allowed
     * @return bool Returns true if null is allowed, otherwise false
     */
    public function allowsNull(): bool {}

    /**
     * Gets parameter position
     * @return int The position of the parameter, left to right, starting at position #0.
     * @since 5.2
     */
    public function getPosition(): int {}

    /**
     * Checks if optional
     * @return bool Returns true if the parameter is optional, otherwise false
     * @since 5.0
     */
    public function isOptional(): bool {}

    /**
     * Checks if a default value is available
     * @return bool Returns true if a default value is available, otherwise false
     * @since 5.0
     */
    public function isDefaultValueAvailable(): bool {}

    /**
     * Gets default parameter value
     * @return mixed The parameters default value.
     * @throws ReflectionException if the parameter is not optional
     * @since 5.0
     */
    public function getDefaultValue(): mixed {}

    /**
     * Returns whether the default value of this parameter is constant
     * @return bool Returns true if the default value is constant, and false otherwise.
     * @since 5.4
     */
    public function isDefaultValueConstant(): bool {}

    /**
     * Returns the default value's constant name if default value is constant or null
     * @return string|null Returns string on success or null on failure.
     * @throws ReflectionException if the parameter is not optional
     * @since 5.4
     */
    public function getDefaultValueConstantName(): ?string {}

    /**
     * Returns whether this function is variadic
     * @return bool Returns true if the function is variadic, otherwise false
     * @since 5.6
     */
    public function isVariadic(): bool {}

    /**
     * Returns information about whether the parameter is a promoted.
     * @return bool Returns true if the parameter promoted or false instead
     * @since 8.0
     */
    public function isPromoted(): bool {}

    /**
     * Gets Attributes
     *
     * Returns all attributes declared on this parameter as an array of ReflectionAttribute.
     * @template T Returns an array of parameter attributes.
     * @param class-string<T>|null $name Name of an attribute class
     * @param int $flags Сriteria by which the attribute is searched.
     * @return ReflectionAttribute<T>[] Array of attributes, as a ReflectionAttribute object.
     * @since 8.0
     */
    public function getAttributes(?string $name = null, int $flags = 0): array {}

    /**
     * Clone
     * @return void
     */
    private function __clone(): void {}

    /**
     * @return string|false
     * @since 8.6
     */
    public function getDocComment(): string|false {}
}
