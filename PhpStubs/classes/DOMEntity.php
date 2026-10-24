<?php

/**
 * The DOMEntity class represents a known entity, either parsed or unparsed, in an XML document.
 */
class DOMEntity extends DOMNode
{
    /**
     * @var string|null The public identifier associated with the entity if specified, and NULL otherwise.
     */
    public string|null $publicId;

    /**
     * @var string|null The system identifier associated with the entity if specified, and NULL otherwise. This may be an absolute URI or not.
     */
    public string|null $systemId;

    /**
     * @var string|null For unparsed entities, the name of the notation for the entity. For parsed entities, this is NULL.
     */
    public string|null $notationName;

    /**
     * @var string|null An attribute specifying the encoding used for this entity at the time of parsing, when it is an external parsed entity. This is NULL if it an entity from the internal subset or if it is not known.
     */
    public string|null $actualEncoding;

    /**
     * @var string|null An attribute specifying, as part of the text declaration, the encoding of this entity, when it is an external parsed entity. This is NULL otherwise.
     */
    public string|null $encoding;

    /**
     * @var string|null An attribute specifying, as part of the text declaration, the version number of this entity, when it is an external parsed entity. This is NULL otherwise.
     */
    public string|null $version;
}
