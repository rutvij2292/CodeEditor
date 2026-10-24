<?php
namespace Random;

use Error;
use Exception;

/**
 * Indicates that the used Random\Engine is broken, e.g. because it is severely biased.
 * @since 8.2
 */
class BrokenRandomEngineError extends RandomError
{

}
