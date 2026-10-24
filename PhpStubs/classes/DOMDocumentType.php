<?php

/**
 * The DOMDocumentType class
 */
class DOMDocumentType extends DOMNode
{
    /**
     * @var string The public identifier of the external subset.
     */
    public string $publicId;

    /**
     * @var string The system identifier of the external subset. This may be an absolute URI or not.
     */
    public string $systemId;

    /**
     * @var string The name of DTD; i.e., the name immediately following the DOCTYPE keyword.
     */
    public string $name;

    /**
     * @var DOMNamedNodeMap<DOMEntity> A DOMNamedNodeMap containing the general entities, both external and internal, declared in the DTD.
     */
    public DOMNamedNodeMap $entities;

    /**
     * @var DOMNamedNodeMap<DOMNotation> A <clasname>DOMNamedNodeMap containing the notations declared in the DTD.
     */
    public DOMNamedNodeMap $notations;

    /**
     * @var string|null The internal subset as a string, or null if there is none. This is does not contain the delimiting square brackets.
     */
    public string|null $internalSubset;
}
