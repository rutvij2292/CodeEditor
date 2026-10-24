<?php
namespace Dom;

/**
 * Represents a named node map for entities and notation nodes of the DTD.
 * @since 8.4
 * @template TDtdNode of Entity|Notation Should be template-covariant but DocBlock::getTagsByName() does not support it
 * @implements \IteratorAggregate<string, TDtdNode>
 */
class DtdNamedNodeMap implements \IteratorAggregate, \Countable
{
    public int $length;

    /**
     * @return TDtdNode|null
     */
    public function item(int $index): Entity|Notation|null {}

    /**
     * @return TDtdNode|null
     */
    public function getNamedItem(string $qualifiedName): Entity|Notation|null {}

    /**
     * @return TDtdNode|null
     */
    public function getNamedItemNS(?string $namespace, string $localName): Entity|Notation|null {}

    public function count(): int {}

    /**
     * @return \Iterator<string, TDtdNode>
     */
    public function getIterator(): \Iterator {}
}
