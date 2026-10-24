<?php

/**
 * This iterator can be used to filter another iterator based on a regular expression.
 */
class RegexIterator extends FilterIterator
{
    /**
     * Return all matches for the current entry @see preg_match_all
     */
    public const ALL_MATCHES = 2;

    /**
     * Return the first match for the current entry @see preg_match
     */
    public const GET_MATCH = 1;

    /**
     * Only execute match (filter) for the current entry @see preg_match
     */
    public const MATCH = 0;

    /**
     * Replace the current entry (Not fully implemented yet) @see preg_replace
     */
    public const REPLACE = 4;

    /**
     * Returns the split values for the current entry @see preg_split
     */
    public const SPLIT = 3;

    /**
     * Special flag: Match the entry key instead of the entry value.
     */
    public const USE_KEY = 1;

    public const INVERT_MATCH = 2;

    public string|null $replacement;

    /**
     * Create a new RegexIterator
     * @param Iterator $iterator The iterator to apply this regex filter to.
     * @param string $pattern The regular expression to match.
     * @param int $mode [optional] Operation mode, see RegexIterator::setMode() for a list of modes.
     * @param int $flags [optional] Special flags, see RegexIterator::setFlags() for a list of available flags.
     * @param int $pregFlags [optional] The regular expression flags. These flags depend on the operation mode parameter
     * @throws \InvalidArgumentException Throws an InvalidArgumentException if the pattern argument is invalid.
     */
    public function __construct(
        Iterator $iterator,
        string $pattern,
        int $mode = self::MATCH,
        int $flags = 0,
        int $pregFlags = 0
    ) {}

    /**
     * Get accept status
     * @return bool true if a match, false otherwise.
     */
    public function accept(): bool {}

    /**
     * Returns operation mode.
     * @return int the operation mode.
     */
    public function getMode(): int {}

    /**
     * Sets the operation mode.
     * @param int $mode The operation mode. The available modes are listed below. The actual meanings of these modes are described in the predefined constants. RegexIterator modes value constant 0 RegexIterator::MATCH 1 RegexIterator::GET_MATCH 2 RegexIterator::ALL_MATCHES 3 RegexIterator::SPLIT 4 ...
     * @return void No value is returned.
     */
    public function setMode(int $mode): void {}

    /**
     * Get flags
     * @return int the set flags.
     */
    public function getFlags(): int {}

    /**
     * Sets the flags.
     * @param int $flags The flags to set, a bitmask of class constants. The available flags are listed below. The actual meanings of these flags are described in the predefined constants. RegexIterator flags value constant 1 RegexIterator::USE_KEY
     * @return void No value is returned.
     */
    public function setFlags(int $flags): void {}

    /**
     * Returns current regular expression
     * @return string
     * @since 5.4
     */
    public function getRegex(): string {}

    /**
     * Returns the regular expression flags.
     * @return int a bitmask of the regular expression flags.
     */
    public function getPregFlags(): int {}

    /**
     * Sets the regular expression flags.
     * @param int $pregFlags The regular expression flags. See RegexIterator::__construct for an overview of available flags.
     * @return void No value is returned.
     */
    public function setPregFlags(int $pregFlags): void {}
}
