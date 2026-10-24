<?php

/**
 * This recursive iterator can filter another recursive iterator via a regular expression.
 */
class RecursiveRegexIterator extends RegexIterator implements RecursiveIterator
{
    /**
     * Creates a new RecursiveRegexIterator.
     * @param RecursiveIterator $iterator The iterator to apply this regex filter to.
     * @param string $pattern The regular expression to match.
     * @param int $mode [optional] Operation mode, see RegexIterator::setMode() for a list of modes.
     * @param int $flags [optional] Special flags, see RegexIterator::setFlags() for a list of available flags.
     * @param int $pregFlags [optional] The regular expression flags. These flags depend on the operation mode parameter
     */
    public function __construct(
        RecursiveIterator $iterator,
        string $pattern,
        int $mode = RegexIterator::MATCH,
        int $flags = 0,
        int $pregFlags = 0
    ) {}

    /**
     * Returns whether an iterator can be obtained for the current entry.
     * @return bool true if an iterator can be obtained for the current entry, otherwise returns false.
     */
    public function hasChildren(): bool {}

    /**
     * Returns an iterator for the current entry.
     * @return RecursiveRegexIterator An iterator for the current entry, if it can be iterated over by the inner iterator.
     * @throws \InvalidArgumentException An InvalidArgumentException will be thrown if the current entry does not contain a value that can be iterated over by the inner iterator.
     */
    public function getChildren(): RecursiveRegexIterator {}
}
