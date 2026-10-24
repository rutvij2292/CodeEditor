<?php

/**
 * Classes implementing Countable can be used with the
 * count function.
 */
interface Countable
{
    /**
     * Count elements of an object
     * @return int<0,max> The custom count as an integer. The return value is cast to an integer.
     */
    public function count(): int;
}
