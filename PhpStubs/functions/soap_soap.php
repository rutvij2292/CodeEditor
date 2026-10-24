<?php

/**
 * Set whether to use the SOAP error handler
 * @param bool $enable [optional] Set to TRUE to send error details to clients.
 * @return bool the original value.
 */
function use_soap_error_handler(bool $enable = true): bool {}

/**
 * Checks if a SOAP call has failed
 * @param mixed $object The object to test.
 * @return bool This will return TRUE on error, and FALSE otherwise.
 */
function is_soap_fault(mixed $object): bool {}
