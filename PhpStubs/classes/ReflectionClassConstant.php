<?php

/**
 * The ReflectionClassConstant class reports information about a class constant.
 * @since 7.1
 */
class ReflectionClassConstant implements Reflector
{
    /**
     * @var string Constant name, same as calling the ReflectionClassConstant::getName() method
     */
    public string $name;

    /**
     * @var class-string Fully qualified class name where this constant was defined
     */
    public string $class;

    /**
     * @var bool
     * @since 8.1
     */
    public bool $isFinal;

    /**
     * Indicates that the constant is public.
     * @since 8.0
     */
    public const IS_PUBLIC = 1;

    /**
     * Indicates that the constant is protected.
     * @since 8.0
     */
    public const IS_PROTECTED = 2;

    /**
     * Indicates that the constant is private.
     * @since 8.0
     */
    public const IS_PRIVATE = 4;

    /**
     * @since 8.1
     */
    public const IS_FINAL = 32;

    /**
     * ReflectionClassConstant constructor.
     * @param class-string|object $class Either a string containing the name of the class to reflect, or an object.
     * @param string $constant The name of the class constant.
     * @since 7.1
     * @throws \Exception Throws an Exception in case the given class constant does not exist.
     */
    public function __construct(string|object $class, string $constant) {}

    /**
     * Export
     *
     * Exports a reflection.
     * @param string|object $class The reflection to export.
     * @param string $name The class constant name.
     * @param bool $return Setting to true will return the export, as opposed to emitting it. Setting to false (the default) will do the opposite.
     * @return string|null
     * @since 7.1
     * @removed 8.0
     * @deprecated
     */
    public static function export($class, $name, $return = false) {}

    /**
     * Gets declaring class
     * @return ReflectionClass A ReflectionClass object.
     * @since 7.1
     */
    public function getDeclaringClass(): ReflectionClass {}

    /**
     * Gets doc comments
     * @return string|false The doc comment if it exists, otherwise false
     * @since 7.1
     */
    public function getDocComment(): string|false {}

    /**
     * Gets the class constant modifiers
     * @return int A numeric representation of the modifiers. The actual meanings of these modifiers are described in the predefined constants.
     * @since 7.1
     */
    public function getModifiers(): int {}

    /**
     * Get name of the constant
     * @return string Returns the constant's name.
     * @since 7.1
     */
    public function getName(): string {}

    /**
     * Gets value
     * @return mixed The value of the class constant.
     * @since 7.1
     */
    public function getValue(): mixed {}

    /**
     * Checks if class constant is private
     * @return bool true if the class constant is private, otherwise false
     * @since 7.1
     */
    public function isPrivate(): bool {}

    /**
     * Checks if class constant is protected
     * @return bool true if the class constant is protected, otherwise false
     * @since 7.1
     */
    public function isProtected(): bool {}

    /**
     * Checks if class constant is public
     * @return bool true if the class constant is public, otherwise false
     * @since 7.1
     */
    public function isPublic(): bool {}

    /**
     * Returns the string representation of the ReflectionClassConstant object.
     * @return string A string representation of this ReflectionClassConstant instance.
     * @since 7.1
     */
    public function __toString(): string {}

    /**
     * Gets Attributes
     *
     * Returns all attributes declared on this class constant as an array of ReflectionAttribute.
     * @template T Returns an array of constant attributes.
     * @param class-string<T>|null $name Name of an attribute class
     * @param int $flags Сriteria by which the attribute is searched.
     * @return ReflectionAttribute<T>[] Array of attributes, as a ReflectionAttribute object.
     * @since 8.0
     */
    public function getAttributes(?string $name = null, int $flags = 0): array {}

    /**
     * ReflectionClassConstant cannot be cloned
     * @return void
     */
    private function __clone(): void {}

    /**
     * Checks if class constant is an Enum case
     *
     * Checks if the class constant is an Enum case.
     * @return bool true if the class constant is an Enum case; false otherwise.
     */
    public function isEnumCase(): bool {}

    /**
     * Checks if class constant is final
     *
     * Checks if the class constant is final.
     * @return bool true if the class constant is final, otherwise false
     * @since 8.1
     */
    public function isFinal(): bool {}

    /**
     * Checks if class constant has a type
     *
     * Checks if the class constant has a type associated with it.
     * @since 8.3
     */
    public function hasType(): bool {}

    /**
     * Gets a class constant's type
     *
     * Gets the associated type of a class constant.
     * @since 8.3
     */
    public function getType(): ?ReflectionType {}

    /**
     * Checks if deprecated
     *
     * Checks whether the class constant is deprecated.
     * @since 8.4
     */
    public function isDeprecated(): bool {}
}
