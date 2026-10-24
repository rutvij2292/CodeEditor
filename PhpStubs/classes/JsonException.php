<?php

/**
 * Class JsonException
 *
 * A new flag has been added, JSON_THROW_ON_ERROR, which can be used with
 * json_decode() or json_encode() and causes these functions to throw a
 * JsonException upon an error, instead of setting the global error state that
 * is retrieved with json_last_error(). JSON_PARTIAL_OUTPUT_ON_ERROR takes
 * precedence over JSON_THROW_ON_ERROR.
 * @since 7.3
 */
class JsonException extends Exception
{

}
