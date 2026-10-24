<?php

/**
 * @since 8.6
 */
enum StreamErrorStore implements \UnitEnum
{
    case Auto;

    case None;

    case NonTerminating;

    case Terminating;

    case All;
}
