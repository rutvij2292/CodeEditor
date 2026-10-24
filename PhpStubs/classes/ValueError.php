<?php

/**
 * Is thrown when the type of an argument is correct but the value of it is incorrect. For example, passing a negative
 * integer when the function expects a positive one, or passing an empty string/array when the function expects it to not be empty.
 * @since 8.0
 */
class ValueError extends Error
{

}
