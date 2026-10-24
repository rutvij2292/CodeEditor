<?php
namespace Random;

use Error;
use Exception;

/**
 * A marker interface indicating that the Random\Engine returns cryptographically secure
 * randomness.
 * @since 8.2
 */
interface CryptoSafeEngine extends Engine
{

}
