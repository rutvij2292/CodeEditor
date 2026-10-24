<?php

/**
 * @since 8.6
 */
class StreamException extends \Exception
{
    /**
     * @var StreamError[]
     */
    private array $errors;

    public function getErrors(): array {}
}
