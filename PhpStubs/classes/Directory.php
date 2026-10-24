<?php

/**
 * Instances of Directory are created by calling the dir() function, not by the new operator.
 */
class Directory
{
    /**
     * @var string The directory that was opened.
     * @removed 8.1
     */
    public $path;

    /**
     * @var string The directory that was opened.
     * @since 8.1
     */
    public readonly string $path;

    /**
     * @var resource Can be used with other directory functions such as readdir(), rewinddir() and closedir().
     * @removed 8.1
     */
    public $handle;

    /**
     * @var resource Can be used with other directory functions such as readdir(), rewinddir() and closedir().
     * @since 8.1
     */
    public readonly mixed $handle;

    /**
     * Close directory handle.
     * Same as closedir(), only dir_handle defaults to $this.
     * @param resource $dir_handle [optional]
     */
    public function close(): void {}

    /**
     * Rewind directory handle.
     * Same as rewinddir(), only dir_handle defaults to $this.
     * @param resource $dir_handle [optional]
     */
    public function rewind(): void {}

    /**
     * Read entry from directory handle.
     * Same as readdir(), only dir_handle defaults to $this.
     * @param resource $dir_handle [optional]
     * @return string|false
     */
    public function read(): string|false {}
}
