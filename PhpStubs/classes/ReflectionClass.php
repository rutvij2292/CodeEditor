<?php

/**
 * The ReflectionClass class reports information about a class.
 * @template T of object The ReflectionClass class reports information about a class.
 */
class ReflectionClass implements Reflector
{
    /**
     * @var class-string<T> Name of the class, same as calling the ReflectionClass::getName() method
     */
    public string $name;

    /**
     * Indicates class that is abstract because it has some abstract methods.
     */
    public const IS_IMPLICIT_ABSTRACT = 16;

    /**
     * Indicates class that is abstract because of its definition.
     */
    public const IS_EXPLICIT_ABSTRACT = 64;

    /**
     * Indicates final class.
     */
    public const IS_FINAL = 32;

    /**
     * @since 8.2
     */
    public const IS_READONLY = 65536;

    /**
     * @since 8.4
     */
    public const int SKIP_INITIALIZATION_ON_SERIALIZE = 8;

    /**
     * @since 8.4
     */
    public const int SKIP_DESTRUCTOR = 16;

    /**
     * Constructs a ReflectionClass
     * @param class-string<T>|T $objectOrClass Either a string containing the name of the class to reflect, or an object.
     * @throws ReflectionException if the class does not exist.
     */
    public function __construct(object|string $objectOrClass) {}

    /**
     * Exports a reflected class
     * @param mixed $argument The reflection to export.
     * @param bool $return Setting to true will return the export, as opposed to emitting it. Setting to false (the default) will do the opposite.
     * @return string|null If the $return parameter is set to true, then the export is returned as a string, otherwise null is returned.
     * @removed 8.0
     * @deprecated
     */
    public static function export($argument, $return = false) {}

    /**
     * Returns the string representation of the ReflectionClass object.
     * @return string A string representation of this ReflectionClass instance.
     */
    public function __toString(): string {}

    /**
     * Gets class name
     * @return string The class name.
     */
    public function getName(): string {}

    /**
     * Checks if class is defined internally by an extension, or the core
     * @return bool Returns true on success or false on failure.
     */
    public function isInternal(): bool {}

    /**
     * Checks if user defined
     * @return bool Returns true on success or false on failure.
     */
    public function isUserDefined(): bool {}

    /**
     * Checks if the class is instantiable
     * @return bool Returns true on success or false on failure.
     */
    public function isInstantiable(): bool {}

    /**
     * Returns whether this class is cloneable
     * @return bool Returns true if the class is cloneable, false otherwise.
     * @since 5.4
     */
    public function isCloneable(): bool {}

    /**
     * Gets the filename of the file in which the class has been defined
     * @return string|false the filename of the file in which the class has been defined. If the class is defined in the PHP core or in a PHP extension, false is returned.
     */
    public function getFileName(): string|false {}

    /**
     * Gets starting line number
     * @return int The starting line number, as an integer.
     */
    public function getStartLine(): int|false {}

    /**
     * Gets end line
     * @return int|false The ending line number of the user defined class, or false if unknown.
     */
    public function getEndLine(): int|false {}

    /**
     * Gets doc comments
     * @return string|false The doc comment if it exists, otherwise false
     */
    public function getDocComment(): string|false {}

    /**
     * Gets the constructor of the class
     * @return ReflectionMethod|null A ReflectionMethod object reflecting the class' constructor, or null if the class has no constructor.
     */
    public function getConstructor(): ?ReflectionMethod {}

    /**
     * Checks if method is defined
     * @param string $name Name of the method being checked for.
     * @return bool Returns true if it has the method, otherwise false
     */
    public function hasMethod(string $name): bool {}

    /**
     * Gets a ReflectionMethod for a class method.
     * @param string $name The method name to reflect.
     * @return ReflectionMethod A ReflectionMethod
     * @throws ReflectionException if the method does not exist.
     */
    public function getMethod(string $name): ReflectionMethod {}

    /**
     * Gets an array of methods for the class.
     * @param int|null $filter Filter the results to include only methods with certain attributes. Defaults to no filtering.
     * @return ReflectionMethod[] An array of ReflectionMethod objects reflecting each method.
     */
    public function getMethods(int|null $filter = null): array {}

    /**
     * Checks if property is defined
     * @param string $name Name of the property being checked for.
     * @return bool Returns true if it has the property, otherwise false
     */
    public function hasProperty(string $name): bool {}

    /**
     * Gets a ReflectionProperty for a class's property
     * @param string $name The property name.
     * @return ReflectionProperty A ReflectionProperty
     * @throws ReflectionException If no property exists by that name.
     */
    public function getProperty(string $name): ReflectionProperty {}

    /**
     * Gets properties
     * @param int|null $filter The optional filter, for filtering desired property types. It's configured using the ReflectionProperty constants, and defaults to all property types.
     * @return ReflectionProperty[] An array of ReflectionProperty objects.
     */
    public function getProperties(int|null $filter = null): array {}

    /**
     * Gets a ReflectionClassConstant for a class's property
     * @param string $name The class constant name.
     * @return ReflectionClassConstant|false A ReflectionClassConstant.
     * @since 7.1
     */
    public function getReflectionConstant(string $name): ReflectionClassConstant|false {}

    /**
     * Gets class constants
     * @param int|null $filter [optional] allows the filtering of constants defined in a class by their visibility. Since 8.0.
     * @return ReflectionClassConstant[] An array of ReflectionClassConstant objects.
     * @since 7.1
     */
    public function getReflectionConstants(?int $filter = null): array {}

    /**
     * Checks if constant is defined
     * @param string $name The name of the constant being checked for.
     * @return bool Returns true if the constant is defined, otherwise false
     */
    public function hasConstant(string $name): bool {}

    /**
     * Gets constants
     * @param int|null $filter [optional] allows the filtering of constants defined in a class by their visibility. Since 8.0.
     * @return array<string, mixed> An array of constants, where the keys hold the name and the values the value of the constants.
     */
    public function getConstants(?int $filter = null): array {}

    /**
     * Gets defined constant
     * @param string $name Name of the constant.
     * @return mixed Value of the constant with the name name. Returns false if the constant was not found in the class.
     */
    public function getConstant(string $name): mixed {}

    /**
     * Gets the interfaces
     * @return ReflectionClass[] An associative array of interfaces, with keys as interface names and the array values as ReflectionClass objects.
     */
    public function getInterfaces(): array {}

    /**
     * Gets the interface names
     * @return string[] A numerical array with interface names as the values.
     */
    public function getInterfaceNames(): array {}

    /**
     * Checks if the class is anonymous
     * @return bool Returns true on success or false on failure.
     * @since 7.0
     */
    public function isAnonymous(): bool {}

    /**
     * Checks if the class is an interface
     * @return bool Returns true on success or false on failure.
     */
    public function isInterface(): bool {}

    /**
     * Returns an array of traits used by this class
     * @return ReflectionClass[] an array with trait names in keys and instances of trait's ReflectionClass in values.
     * @since 5.4
     */
    public function getTraits(): array {}

    /**
     * Returns an array of names of traits used by this class
     * @return string[] An array with trait names in values. Returns null in case of an error.
     * @since 5.4
     */
    public function getTraitNames(): array {}

    /**
     * Returns an array of trait aliases
     * @return string[] an array with new method names in keys and original names (in the format "TraitName::original") in values. Returns null in case of an error.
     * @since 5.4
     */
    public function getTraitAliases(): array {}

    /**
     * Returns whether this is a trait
     * @return bool Returns true if this is a trait, false otherwise. Returns null in case of an error.
     * @since 5.4
     */
    public function isTrait(): bool {}

    /**
     * Checks if class is abstract
     * @return bool Returns true on success or false on failure.
     */
    public function isAbstract(): bool {}

    /**
     * Checks if class is final
     * @return bool Returns true on success or false on failure.
     */
    public function isFinal(): bool {}

    /**
     * Checks if class is readonly
     *
     * Checks if a class is readonly.
     * @return bool true if a class is readonly, false otherwise.
     */
    public function isReadOnly(): bool {}

    /**
     * Gets modifiers
     * @return int bitmask of modifier constants.
     */
    public function getModifiers(): int {}

    /**
     * Checks class for instance
     * @param object $object The object being compared to.
     * @return bool Returns true on success or false on failure.
     */
    public function isInstance(object $object): bool {}

    /**
     * Creates a new class instance from given arguments.
     * @param mixed ...$args Accepts a variable number of arguments which are passed to the class constructor, much like call_user_func
     * @return T a new instance of the class.
     * @throws ReflectionException if the class constructor is not public or if the class does not have a constructor and the $args parameter contains one or more parameters.
     */
    public function newInstance(mixed ...$args): object {}

    /**
     * Creates a new class instance without invoking the constructor.
     * @return T a new instance of the class.
     * @throws ReflectionException if the class is an internal class that cannot be instantiated without invoking the constructor. In PHP 5.6.0 onwards, this exception is limited only to internal classes that are final.
     * @since 5.4
     */
    public function newInstanceWithoutConstructor(): object {}

    /**
     * Creates a new class instance from given arguments.
     * @param array $args The parameters to be passed to the class constructor as an array.
     * @return T|null a new instance of the class.
     * @throws ReflectionException if the class constructor is not public or if the class does not have a constructor and the $args parameter contains one or more parameters.
     * @since 5.1
     */
    public function newInstanceArgs(array $args = []): ?object {}

    /**
     * Gets parent class
     * @return ReflectionClass|false A ReflectionClass or false if there's no parent.
     */
    public function getParentClass(): ReflectionClass|false {}

    /**
     * Checks if a subclass
     * @param string|ReflectionClass $class Either the name of the class as string or a ReflectionClass object of the class to check against.
     * @return bool true on success or false on failure.
     */
    public function isSubclassOf(ReflectionClass|string $class): bool {}

    /**
     * Gets static properties
     * @return array|null The static properties, as an array where the keys hold the name and the values the value of the properties.
     */
    public function getStaticProperties(): array {}

    /**
     * Gets static property value
     * @param string $name The name of the static property for which to return a value.
     * @param mixed $default [optional] A default value to return in case the class does not declare a static property with the given name. If the property does not exist and this argument is omitted, a ReflectionException is thrown.
     * @return mixed The value of the static property.
     */
    public function getStaticPropertyValue(
        string $name,
        mixed $default
    ): mixed {}

    /**
     * Sets static property value
     * @param string $name Property name.
     * @param mixed $value New property value.
     * @return void No value is returned.
     */
    public function setStaticPropertyValue(
        string $name,
        mixed $value
    ): void {}

    /**
     * Gets default properties
     * @return mixed[] An array of default properties, with the key being the name of the property and the value being the default value of the property or null if the property doesn't have a default value. The function does not distinguish between static and non static properties and does not take ...
     */
    public function getDefaultProperties(): array {}

    /**
     * An alias of ReflectionClass::isIterable method.
     * @return bool Returns true on success or false on failure.
     */
    public function isIterateable(): bool {}

    /**
     * Check whether this class is iterable
     * @return bool Returns true on success or false on failure.
     * @since 7.2
     */
    public function isIterable(): bool {}

    /**
     * Checks whether it implements an interface.
     * @param string $interface The interface name.
     * @return bool Returns true on success or false on failure.
     * @throws \ReflectionException ReflectionClass::implementsInterface throws an ReflectionException if interface is not an interface.
     */
    public function implementsInterface(ReflectionClass|string $interface): bool {}

    /**
     * Gets a ReflectionExtension object for the extension which defined the class
     * @return ReflectionExtension|null A ReflectionExtension object representing the extension which defined the class, or null for user-defined classes.
     */
    public function getExtension(): ?ReflectionExtension {}

    /**
     * Gets the name of the extension which defined the class
     * @return string|false The name of the extension which defined the class, or false for user-defined classes.
     */
    public function getExtensionName(): string|false {}

    /**
     * Checks if in namespace
     * @return bool true on success or false on failure.
     */
    public function inNamespace(): bool {}

    /**
     * Gets namespace name
     * @return string The namespace name.
     */
    public function getNamespaceName(): string {}

    /**
     * Gets short name
     * @return string The class short name.
     */
    public function getShortName(): string {}

    /**
     * Gets Attributes
     *
     * Returns all attributes declared on this class as an array of ReflectionAttribute.
     * @template T Returns an array of class attributes.
     * @param class-string<T>|null $name Name of an attribute class
     * @param int $flags Сriteria by which the attribute is searched.
     * @return ReflectionAttribute<T>[] Array of attributes, as a ReflectionAttribute object.
     * @since 8.0
     */
    public function getAttributes(?string $name = null, int $flags = 0): array {}

    /**
     * Clones object
     * @return void
     */
    private function __clone(): void {}

    /**
     * Returns whether this is an enum
     *
     * Checks if a class is an enum.
     * @return bool Returns true if this is an enum, false otherwise.
     */
    public function isEnum(): bool {}

    /**
     * Creates a new lazy ghost instance
     *
     * Creates a new lazy ghost instance of the class, attaching the initializer to it. The
     * constructor is not called, and properties are not set to their default value. However, the
     * object will be automatically initialized by invoking the initializer the first time its state
     * is observed or modified. See Initialization Triggers and Initialization Sequence.
     * @since 8.4
     * @throws \Error An Error if the class is internal or extends an internal class except stdClass.
     */
    public function newLazyGhost(callable $initializer, int $options = 0): object {}

    /**
     * Creates a new lazy proxy instance
     *
     * Creates a new lazy proxy instance of the class, attaching the factory function to it. The
     * constructor is not called, and properties are not set to their default values. When an
     * attempt is made to observe or modify the proxy's state for the first time, the factory
     * function is called to provide a real instance, which is then attached to the proxy. After
     * this, all subsequent interactions with the proxy are forwarded to the real instance. See
     * Initialization Triggers and Initialization Sequence.
     * @return T Returns a lazy proxy instance. If the object has no properties, or if all its properties are static or virtual, a normal (non-lazy) instance is returned. See also Lifecycle of Lazy Objects.
     * @since 8.4
     */
    public function newLazyProxy(callable $factory, int $options = 0): object {}

    /**
     * Resets an object and marks it as lazy
     *
     * Resets an existing object and marks it as lazy.
     * @since 8.4
     * @throws \ReflectionException A ReflectionException if the object is lazy and non-initialized.
     * @throws \Error An Error if the object is being initialized, or if the object properties are being iterated with foreach.
     */
    public function resetAsLazyGhost(object $object, callable $initializer, int $options = 0): void {}

    /**
     * Resets an object and marks it as lazy
     *
     * The behavior of this method is the same as ReflectionClass::resetAsLazyGhost except that it
     * uses the proxy strategy.
     * @since 8.4
     */
    public function resetAsLazyProxy(object $object, callable $factory, int $options = 0): void {}

    /**
     * Forces initialization of a lazy object
     *
     * Forces initialization of the specified object. This method has no effect if the object is not
     * lazy or has already been initialized. Otherwise, initialization proceeds as described in the
     * Initialization Sequence.
     * @since 8.4
     */
    public function initializeLazyObject(object $object): object {}

    /**
     * Checks if an object is lazy and uninitialized
     * @since 8.4
     */
    public function isUninitializedLazyObject(object $object): bool {}

    /**
     * Marks a lazy object as initialized without calling the initializer or factory
     *
     * Marks a lazy object as initialized without calling the initializer or factory. This has no
     * effect if object is not lazy or is already initialized.
     * @since 8.4
     */
    public function markLazyObjectAsInitialized(object $object): object {}

    /**
     * Gets lazy initializer
     *
     * Gets the lazy initializer or factory attached to object.
     * @since 8.4
     */
    public function getLazyInitializer(object $object): ?callable {}
}
