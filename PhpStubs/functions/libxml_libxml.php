<?php

/**
 * Set the streams context for the next libxml document load or write
 * @param resource $context The stream context resource (created with stream_context_create)
 * @return void No value is returned.
 * @throws \TypeError Throws a TypeError when a non-stream resource is passed to context.
 */
function libxml_set_streams_context($context): void {}

/**
 * Disable libxml errors and allow user to fetch error information as needed
 * @param bool|null $use_errors Enable (TRUE) user error handling or disable (FALSE) user error handling. Disabling will also clear any existing libxml errors.
 * @return bool This function returns the previous value of use_errors.
 */
function libxml_use_internal_errors(
    ?bool $use_errors = null
): bool {}

/**
 * Retrieve last error from libxml
 * @return LibXMLError|false a LibXMLError object if there is any error in the buffer, FALSE otherwise.
 */
function libxml_get_last_error(): LibXMLError|false {}

/**
 * Clear libxml error buffer
 * @return void No value is returned.
 */
function libxml_clear_errors(): void {}

/**
 * Retrieve array of errors
 * @return LibXMLError[] an array with LibXMLError objects if there are any errors in the buffer, or an empty array otherwise.
 */
function libxml_get_errors(): array {}

/**
 * Disable the ability to load external entities
 * @param bool $disable [optional] Disable (TRUE) or enable (FALSE) libxml extensions (such as , and ) to load external entities.
 * @return bool the previous value.
 * @since 5.2
 * @deprecated
 */
function libxml_disable_entity_loader(bool $disable = true): bool {}

/**
 * Changes the default external entity loader
 * @param callable|null $resolver_function A callable that takes three arguments. Two strings, a public id and system id, and a context (an array with four keys) as the third argument. This callback should return a resource, a string from which a resource can be opened, or NULL.
 * @return bool Always returns true.
 * @since 5.4
 */
function libxml_set_external_entity_loader(?callable $resolver_function): bool {}

/**
 * Returns the currently installed external entity loader, i.e. the value which was passed to
 * libxml_set_external_entity_loader() or null if no loader was installed and the default entity loader will be used.
 * This allows libraries to save and restore the loader, controlling entity expansion without interfering with the rest
 * of the application.
 * @return callable|null The external entity loader previously installed by libxml_set_external_entity_loader. If that function was never called, or if it was called with null, null will be returned.
 * @since 8.2
 */
function libxml_get_external_entity_loader(): ?callable {}
