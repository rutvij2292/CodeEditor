<?php

/**
 * Localized software products often require sets of data that are to be customized depending on
 * current locale, e.g.: messages, labels, formatting patterns. ICU resource mechanism allows to
 * define sets of resources that the application can load on locale basis, while accessing them in
 * unified locale-independent fashion.
 *
 * This class implements access to ICU resource data files. These files are binary data arrays which
 * ICU uses to store the localized data. ICU resource bundle can hold simple resources and complex
 * resources. Complex resources are containers which can be either integer-indexed or string-indexed
 * (just like PHP arrays). Simple resources can be of the following types: string, ...
 */
class ResourceBundle implements IteratorAggregate, Countable
{
    /**
     * Create a resource bundle
     *
     * Creates a resource bundle.
     * @param string $locale Locale for which the resources should be loaded (locale name, e.g. en_CA).
     * @param string $bundle The directory where the data is stored or the name of the .dat file.
     * @param bool $fallback [optional] Whether locale should match exactly or fallback to parent locale is allowed.
     */
    public function __construct(
        $locale,
        $bundle,
        $fallback = true
    ) {}

    /**
     * Create a resource bundle
     * @param string $locale Locale for which the resources should be loaded (locale name, e.g. en_CA).
     * @param string $bundle The directory where the data is stored or the name of the .dat file.
     * @param bool $fallback [optional] Whether locale should match exactly or fallback to parent locale is allowed.
     * @return ResourceBundle|null ResourceBundle object or null on error.
     */
    public static function create(
        $locale,
        $bundle,
        $fallback = true
    ): ?ResourceBundle {}

    /**
     * Get data from the bundle
     * @param string|int $index Data index, must be string or integer.
     * @param bool $fallback Whether locale should match exactly or fallback to parent locale is allowed.
     * @return mixed the data located at the index or NULL on error. Strings, integers and binary data strings are returned as corresponding PHP types, integer array is returned as PHP array. Complex types are returned as ResourceBundle object.
     */
    public function get($index, $fallback = true) {}

    /**
     * Get number of elements in the bundle
     * @return int<0,max> number of elements in the bundle.
     */
    public function count(): int {}

    /**
     * Get supported locales
     * @param string $bundle Path of ResourceBundle for which to get available locales, or empty string for default locales list.
     * @return array|false the list of locales supported by the bundle.
     */
    public static function getLocales($bundle): array|false {}

    /**
     * Get bundle's last error code.
     * @return int error code from last bundle object call.
     */
    public function getErrorCode(): int {}

    /**
     * Get bundle's last error message.
     * @return string error message from last bundle object's call.
     */
    public function getErrorMessage(): string {}

    /**
     * @return Iterator
     * @since 8.0
     */
    public function getIterator(): Iterator {}
}
