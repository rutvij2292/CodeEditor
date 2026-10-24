<?php

/**
 * The ReflectionExtension class reports information about an extension.
 */
class ReflectionExtension implements Reflector
{
    /**
     * @var string Name of the extension, same as calling the ReflectionExtension::getName() method
     */
    public string $name;

    /**
     * Constructs a ReflectionExtension
     * @param string $name Name of the extension.
     * @throws ReflectionException if the extension does not exist.
     */
    public function __construct(string $name) {}

    /**
     * Exports a reflected extension.
     * The output format of this function is the same as the CLI argument --re [extension].
     * @param string $name The reflection to export.
     * @param bool $return Setting to true will return the export, as opposed to emitting it. Setting to false (the default) will do the opposite.
     * @return string|null If the $return parameter is set to true, then the export is returned as a string, otherwise null is returned.
     * @removed 8.0
     * @deprecated
     */
    public static function export($name, $return = false) {}

    /**
     * To string
     * @return string the exported extension as a string, in the same way as the ReflectionExtension::export().
     */
    public function __toString(): string {}

    /**
     * Gets extension name
     * @return string The extensions name.
     */
    public function getName(): string {}

    /**
     * Gets extension version
     * @return string|null The version of the extension.
     */
    public function getVersion(): ?string {}

    /**
     * Gets extension functions
     * @return ReflectionFunction[] An associative array of ReflectionFunction objects, for each function defined in the extension with the keys being the function names. If no function are defined, an empty array is returned.
     */
    public function getFunctions(): array {}

    /**
     * Gets constants
     * @return array An associative array with constant names as keys.
     */
    public function getConstants(): array {}

    /**
     * Gets extension ini entries
     * @return array An associative array with the ini entries as keys, with their defined values as values.
     */
    public function getINIEntries(): array {}

    /**
     * Gets classes
     * @return ReflectionClass[] An array of ReflectionClass objects, one for each class within the extension. If no classes are defined, an empty array is returned.
     */
    public function getClasses(): array {}

    /**
     * Gets class names
     * @return string[] An array of class names, as defined in the extension. If no classes are defined, an empty array is returned.
     */
    public function getClassNames(): array {}

    /**
     * Gets dependencies
     * @return string[] An associative array with dependencies as keys and either Required, Optional or Conflicts as the values.
     */
    public function getDependencies(): array {}

    /**
     * Print extension info
     * @return void Print extension info
     */
    public function info(): void {}

    /**
     * Returns whether this extension is persistent
     * @return bool Returns true for extensions loaded by extension, false otherwise.
     * @since 5.4
     */
    public function isPersistent(): bool {}

    /**
     * Returns whether this extension is temporary
     * @return bool Returns true for extensions loaded by dl(), false otherwise.
     * @since 5.4
     */
    public function isTemporary(): bool {}

    /**
     * Clones
     * @return void No value is returned, if called a fatal error will occur.
     */
    private function __clone(): void {}
}
