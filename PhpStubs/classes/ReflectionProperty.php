<?php

/**
 * The ReflectionProperty class reports information about a classes
 * properties.
 */
class ReflectionProperty implements Reflector
{
    /**
     * @since 8.4
     */
    public const IS_ABSTRACT = 64;

    /**
     * @since 8.4
     */
    public const IS_VIRTUAL = 512;

    /**
     * @var string Name of the property, same as calling the ReflectionProperty::getName() method
     */
    public string $name;

    /**
     * @var class-string Fully qualified class name where this property was defined
     */
    public string $class;

    /**
     * Indicates that the property is static.
     */
    public const IS_STATIC = 16;

    /**
     * Indicates that the property is public.
     */
    public const IS_PUBLIC = 1;

    /**
     * Indicates that the property is protected.
     */
    public const IS_PROTECTED = 2;

    /**
     * Indicates that the property is private.
     */
    public const IS_PRIVATE = 4;

    /**
     * @since 8.1
     */
    public const IS_READONLY = 128;

    /**
     * @since 8.4
     */
    public const IS_PROTECTED_SET = 2048;

    /**
     * @since 8.4
     */
    public const IS_PRIVATE_SET = 4096;

    /**
     * @since 8.4
     */
    public const IS_FINAL = 32;

    /**
     * Construct a ReflectionProperty object
     * @param class-string|object $class The class name, that contains the property.
     * @param string $property The name of the property being reflected.
     * @throws ReflectionException if the class or property does not exist.
     */
    public function __construct(
        object|string $class,
        string $property
    ) {}

    /**
     * Export
     * @param mixed $class The reflection to export.
     * @param string $name The property name.
     * @param bool $return Setting to true will return the export, as opposed to emitting it. Setting to false (the default) will do the opposite.
     * @return string|null
     * @removed 8.0
     * @deprecated
     */
    public static function export($class, $name, $return = false) {}

    /**
     * To string
     * @return string A string representation of this ReflectionProperty instance.
     */
    public function __toString(): string {}

    /**
     * Gets property name
     * @return string The name of the reflected property.
     */
    public function getName(): string {}

    /**
     * Gets value
     * @param object|null $object If the property is non-static an object must be provided to fetch the property from. If you want to fetch the default property without providing an object use ReflectionClass::getDefaultProperties instead.
     * @return mixed The current value of the property.
     */
    public function getValue(object|null $object = null): mixed {}

    /**
     * Set property value
     * @param mixed $objectOrValue If the property is non-static an object must be provided to change the property on. If the property is static this parameter is left out and only $value needs to be provided.
     * @param mixed $value [optional] The new value.
     * @return void No value is returned.
     */
    public function setValue(
        mixed $objectOrValue,
        mixed $value
    ): void {}

    /**
     * Checks if property is public
     * @return bool Return true if the property is public, false otherwise.
     */
    public function isPublic(): bool {}

    /**
     * Checks if property is private
     * @return bool Return true if the property is private, false otherwise.
     */
    public function isPrivate(): bool {}

    /**
     * Checks if property is protected
     * @return bool Returns true if the property is protected, false otherwise.
     */
    public function isProtected(): bool {}

    /**
     * Checks if property is static
     * @return bool Returns true if the property is static, false otherwise.
     */
    public function isStatic(): bool {}

    /**
     * Checks if default value
     * @return bool Returns true if the property was declared at compile-time, or false if it was created at run-time.
     */
    public function isDefault(): bool {}

    /**
     * Gets modifiers
     * @return int A numeric representation of the modifiers.
     */
    public function getModifiers(): int {}

    /**
     * Gets declaring class
     * @return ReflectionClass A ReflectionClass object.
     */
    public function getDeclaringClass(): ReflectionClass {}

    /**
     * Gets doc comment
     * @return string|false The doc comment if it exists, otherwise false
     */
    public function getDocComment(): string|false {}

    /**
     * Set property accessibility
     * This method is no-op starting from PHP 8.1
     * @param bool $accessible A boolean true to allow accessibility, or false
     * @return void No value is returned.
     */
    public function setAccessible(bool $accessible): void {}

    /**
     * Gets property type
     * @return ReflectionNamedType|ReflectionUnionType|null Returns a ReflectionType if the property has a type, and null otherwise.
     * @since 7.4
     */
    public function getType(): ?ReflectionType {}

    /**
     * Checks if property has type
     * @return bool Returns true if a type is specified, false otherwise.
     * @since 7.4
     */
    public function hasType(): bool {}

    /**
     * Checks if property is initialized
     * @param object|null $object If the property is non-static an object must be provided to fetch the property from.
     * @return bool Returns false for typed properties prior to initialization, and for properties that have been explicitly unset(). For all other properties true will be returned.
     * @since 7.4
     * @throws \ReflectionException Throws a ReflectionException if the property is inaccessible. You can make a protected or private property accessible using ReflectionProperty::setAccessible.
     */
    public function isInitialized(?object $object = null): bool {}

    /**
     * Returns information about whether the property was promoted.
     * @return bool Returns true if the property was promoted or false instead.
     * @since 8.0
     */
    public function isPromoted(): bool {}

    /**
     * Clone
     * @return void
     */
    private function __clone(): void {}

    /**
     * Checks if property has a default value declared
     *
     * Checks whether the property was declared with a default value, including an implicit null
     * default value. Only returns false for typed properties without default value (or dynamic
     * properties).
     * @return bool If the property has any default value (including null) true is returned; if the property is typed without a default value declared or is a dynamic property, false is returned.
     * @since 8.0
     */
    public function hasDefaultValue(): bool {}

    /**
     * Returns the default value declared for a property
     *
     * Gets the implicit or explicitly declared default value for a property.
     * @return mixed The default value if the property has any default value (including null). If there is no default value, then null is returned. It is not possible to differentiate between a null default value and an uninitialized typed property. Use ReflectionProperty::hasDefaultValue to detect the ...
     * @since 8.0
     */
    public function getDefaultValue(): mixed {}

    /**
     * Gets Attributes
     *
     * Returns all attributes declared on this class property as an array of ReflectionAttribute.
     * @template T Returns an array of property attributes.
     * @param class-string<T>|null $name Name of an attribute class
     * @param int $flags Сriteria by which the attribute is searched.
     * @return ReflectionAttribute<T>[] Array of attributes, as a ReflectionAttribute object.
     * @since 8.0
     */
    public function getAttributes(?string $name = null, int $flags = 0): array {}

    /**
     * Checks if property is readonly
     *
     * Checks whether the property is readonly.
     * @return bool true if the property is readonly, false otherwise.
     * @since 8.1
     */
    public function isReadOnly(): bool {}

    /**
     * Returns the value of a property, bypassing a get hook if defined
     * @since 8.4
     * @throws \Error If the property is virtual, an Error will be thrown, as there is no raw value to retrieve.
     */
    public function getRawValue(object $object): mixed {}

    /**
     * Sets the value of a property, bypassing a set hook if defined
     * @since 8.4
     * @throws \Error If the property is virtual, an Error will be thrown, as there is no raw value to set.
     */
    public function setRawValue(object $object, mixed $value): void {}

    /**
     * Determines if a property is abstract
     * @since 8.4
     */
    public function isAbstract(): bool {}

    /**
     * Determines if a property is virtual
     * @since 8.4
     */
    public function isVirtual(): bool {}

    /**
     * Returns the parameter type of a setter hook
     *
     * Returns the parameter type of a set hook. If no set hook is defined, it behaves identically
     * to ReflectionProperty::getType.
     * @since 8.4
     */
    public function getSettableType(): ?ReflectionType {}

    /**
     * Returns whether the property has any hooks defined
     * @since 8.4
     */
    public function hasHooks(): bool {}

    /**
     * Returns an array of all hooks on this property
     *
     * Returns a list of all hooks on this property.
     * @since 8.4
     */
    public function getHooks(): array {}

    /**
     * Returns whether the property has a given hook defined
     * @since 8.4
     */
    public function hasHook(PropertyHookType $type): bool {}

    /**
     * Returns a reflection object for a specified hook
     *
     * Gets the reflection of the property's hook, if any.
     * @since 8.4
     */
    public function getHook(PropertyHookType $type): ?ReflectionMethod {}

    /**
     * Checks if property is private for writing
     *
     * Checks whether the property is private for writing.
     * @since 8.4
     */
    public function isPrivateSet(): bool {}

    /**
     * Checks whether the property is protected for writing
     * @since 8.4
     */
    public function isProtectedSet(): bool {}

    /**
     * Set raw property value without triggering lazy initialization
     *
     * Sets (changes) the property's value without triggering lazy initialization and without
     * calling hook functions. The property is marked as non-lazy and can be accessed afterwards
     * without triggering lazy initialization. The property must not be dynamic, static, or virtual,
     * and the object must be an instance of a user defined class or stdClass.
     * @since 8.4
     */
    public function setRawValueWithoutLazyInitialization(object $object, mixed $value): void {}

    /**
     * Marks property as non-lazy
     *
     * Marks a property as non-lazy such that it can be accessed directly without triggering lazy
     * initialization. The property is initialized to its default value, if any. The property must
     * not be dynamic, static, or virtual, and the object must be an instance of a user defined
     * class or stdClass.
     * @since 8.4
     */
    public function skipLazyInitialization(object $object): void {}

    /**
     * Checks if property is a dynamic property
     *
     * Checks whether the property was declared at run-time, or whether the property was declared at
     * compile-time.
     * @since 8.4
     */
    public function isDynamic(): bool {}

    /**
     * Determines if this property is final or not
     *
     * Returns whether the property is final. If the property is marked private(set), then it will
     * also be implicitly final.
     * @since 8.4
     */
    public function isFinal(): bool {}

    /**
     * Checks whether a property is lazy
     * @since 8.4
     */
    public function isLazy(object $object): bool {}

    /**
     * Gets the mangled name of the property
     *
     * Returns the mangled (internal) name of the property, which encodes the visibility scope for
     * private and protected properties.
     * @since 8.5
     */
    public function getMangledName(): string {}

    /**
     * @param string|null $scope
     * @param object|null $object
     * @return bool
     * @since 8.6
     */
    public function isReadable(?string $scope, ?object $object = null): bool {}

    /**
     * @param string|null $scope
     * @param object|null $object
     * @return bool
     * @since 8.6
     */
    public function isWritable(?string $scope, ?object $object = null): bool {}
}
