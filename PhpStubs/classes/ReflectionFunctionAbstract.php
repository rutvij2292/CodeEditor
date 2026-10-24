<?php

/**
 * A parent class to ReflectionFunction, read its
 * description for details.
 */
abstract class ReflectionFunctionAbstract implements Reflector
{
    /**
     * @var string Name of the function, same as calling the ReflectionFunctionAbstract::getName() method
     */
    public string $name;

    /**
     * Clones function
     * @return void No value is returned.
     */
    private function __clone(): void {}

    /**
     * Checks if function in namespace
     * @return bool true if it's in a namespace, otherwise false
     */
    public function inNamespace(): bool {}

    /**
     * Checks if closure
     * @return bool true if it's a closure, otherwise false
     */
    public function isClosure(): bool {}

    /**
     * Checks if deprecated
     * @return bool true if it's deprecated, otherwise false
     */
    public function isDeprecated(): bool {}

    /**
     * Checks if is internal
     * @return bool true if it's internal, otherwise false
     */
    public function isInternal(): bool {}

    /**
     * Checks if user defined
     * @return bool true if it's user-defined, otherwise false
     */
    public function isUserDefined(): bool {}

    /**
     * Returns whether this function is a generator
     * @return bool true if the function is generator, otherwise false
     * @since 5.5
     */
    public function isGenerator(): bool {}

    /**
     * Returns whether this function is variadic
     * @return bool true if the function is variadic, otherwise false
     * @since 5.6
     */
    public function isVariadic(): bool {}

    /**
     * Returns this pointer bound to closure
     * @return object|null Returns $this pointer or null in case of an error.
     */
    public function getClosureThis(): ?object {}

    /**
     * Returns the scope associated to the closure
     * @return ReflectionClass|null Returns the class on success or null on failure.
     * @since 5.4
     */
    public function getClosureScopeClass(): ?ReflectionClass {}

    /**
     * Returns the class corresponding to static:: inside a closure
     *
     * Returns the class as a ReflectionClass that corresponds to resolving the class name
     * corresponding to static:: inside the Closure.
     * @return ReflectionClass|null Returns the class on success or null on failure.
     * @since 8.0
     */
    public function getClosureCalledClass(): ?ReflectionClass {}

    /**
     * Gets doc comment
     * @return string|false The doc comment if it exists, otherwise false
     */
    public function getDocComment(): string|false {}

    /**
     * Gets end line number
     * @return int|false The ending line number of the user defined function, or false if unknown.
     */
    public function getEndLine(): int|false {}

    /**
     * Gets extension info
     * @return ReflectionExtension|null The extension information, as a ReflectionExtension object or null instead.
     */
    public function getExtension(): ?ReflectionExtension {}

    /**
     * Gets extension name
     * @return string|false The extension's name or false instead.
     */
    public function getExtensionName(): string|false {}

    /**
     * Gets file name
     * @return string|false The file name or false in case of error.
     */
    public function getFileName(): string|false {}

    /**
     * Gets function name
     * @return string The name of the function.
     */
    public function getName(): string {}

    /**
     * Gets namespace name
     * @return string The namespace name.
     */
    public function getNamespaceName(): string {}

    /**
     * Gets number of parameters
     * @return int The number of parameters.
     * @since 5.0
     */
    public function getNumberOfParameters(): int {}

    /**
     * Gets number of required parameters
     * @return int The number of required parameters.
     * @since 5.0
     */
    public function getNumberOfRequiredParameters(): int {}

    /**
     * Gets parameters
     * @return ReflectionParameter[] The parameters, as a ReflectionParameter objects.
     */
    public function getParameters(): array {}

    /**
     * Gets the specified return type of a function
     * @return ReflectionType|null Returns a ReflectionType object if a return type is specified, null otherwise.
     * @since 7.0
     */
    public function getReturnType(): ?ReflectionType {}

    /**
     * Gets function short name
     * @return string The short name of the function.
     */
    public function getShortName(): string {}

    /**
     * Gets starting line number
     * @return int|false The starting line number or false if unknown.
     */
    public function getStartLine(): int|false {}

    /**
     * Gets static variables
     * @return array An array of static variables.
     */
    public function getStaticVariables(): array {}

    /**
     * Checks if returns reference
     * @return bool true if it returns a reference, otherwise false
     */
    public function returnsReference(): bool {}

    /**
     * Checks if the function has a specified return type
     * @return bool Returns true if the function is a specified return type, otherwise false.
     * @since 7.0
     */
    public function hasReturnType(): bool {}

    /**
     * Gets Attributes
     *
     * Returns all attributes declared on this function or method as an array of
     * ReflectionAttribute.
     * @template T Returns an array of function attributes.
     * @param class-string<T>|null $name Name of an attribute class
     * @param int $flags Сriteria by which the attribute is searched.
     * @return ReflectionAttribute<T>[] Array of attributes, as a ReflectionAttribute object.
     * @since 8.0
     */
    public function getAttributes(?string $name = null, int $flags = 0): array {}

    /**
     * Returns an array of the used variables in the Closure
     * @return array Returns an array of the used variables in the Closure.
     */
    public function getClosureUsedVariables(): array {}

    /**
     * Returns whether the function has a tentative return type
     * @return bool Returns true if the function has a tentative return type, otherwise false.
     */
    public function hasTentativeReturnType(): bool {}

    /**
     * Returns the tentative return type associated with the function
     * @return ReflectionType|null Returns a ReflectionType object if a tentative return type is specified, null otherwise.
     */
    public function getTentativeReturnType(): ?ReflectionType {}

    /**
     * Checks if the function is static
     * @return bool true if the function is static, otherwise false
     */
    public function isStatic(): bool {}

    /**
     * Returns the string representation of the ReflectionFunctionAbstract object
     *
     * Get a human-readable description of the function, its parameters and return values.
     */
    public function __toString(): string {}
}
