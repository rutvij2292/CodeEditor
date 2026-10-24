<?php

/**
 * The ReflectionZendExtension class reports information about a zend extension.
 * @since 5.4
 */
class ReflectionZendExtension implements Reflector
{
    /**
     * @var string Name of the extension, same as calling the ReflectionZendExtension::getName() method
     */
    public string $name;

    /**
     * Constructs a ReflectionZendExtension object
     * @param string $name The extension name.
     * @throws ReflectionException if the extension does not exist.
     * @since 5.4
     */
    public function __construct(string $name) {}

    /**
     * Exports a reflected zend extension.
     * @param string $name The reflection to export.
     * @param bool $return Setting to true will return the export, as opposed to emitting it. Setting to false (the default) will do the opposite.
     * @return string|null If the $return parameter is set to true, then the export is returned as a string, otherwise null is returned.
     * @removed 8.0
     * @deprecated
     */
    public static function export($name, $return = false) {}

    /**
     * To string handler
     * @return string
     * @since 5.4
     */
    public function __toString(): string {}

    /**
     * Gets name
     * @return string
     * @since 5.4
     */
    public function getName(): string {}

    /**
     * Gets version
     * @return string
     * @since 5.4
     */
    public function getVersion(): string {}

    /**
     * Gets author
     * @return string
     * @since 5.4
     */
    public function getAuthor(): string {}

    /**
     * Gets URL
     * @return string
     * @since 5.4
     */
    public function getURL(): string {}

    /**
     * Gets copyright
     * @return string
     * @since 5.4
     */
    public function getCopyright(): string {}

    /**
     * Clone handler
     * @return void
     * @since 5.4
     */
    private function __clone(): void {}
}
