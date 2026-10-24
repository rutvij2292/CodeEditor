<?php

/**
 * A class representing a variable or object for use with SOAP services.
 */
class SoapVar
{
    /**
     * @var int
     * @since 8.1
     */
    public int $enc_type;

    /**
     * @var mixed
     * @since 8.1
     */
    public mixed $enc_value;

    /**
     * @var string|null
     * @since 8.1
     */
    public string|null $enc_stype;

    /**
     * @var string|null
     * @since 8.1
     */
    public string|null $enc_ns;

    /**
     * @var string|null
     * @since 8.1
     */
    public string|null $enc_name;

    /**
     * @var string|null
     * @since 8.1
     */
    public string|null $enc_namens;

    /**
     * SoapVar constructor
     * @param mixed $data The data to pass or return.
     * @param int|null $encoding The encoding ID, one of the XSD_... constants.
     * @param string $typeName [optional] The type name.
     * @param string $typeNamespace [optional] The type namespace.
     * @param string $nodeName [optional] The XML node name.
     * @param string $nodeNamespace [optional] The XML node namespace.
     * @since 5.0
     */
    public function __construct(
        mixed $data,
        int|null $encoding,
        string|null $typeName = null,
        string|null $typeNamespace = null,
        string|null $nodeName = null,
        string|null $nodeNamespace = null
    ) {}

    /**
     * SoapVar constructor
     * @param mixed $data The data to pass or return.
     * @param int|null $encoding The encoding ID, one of the XSD_... constants.
     * @param string $type_name [optional] The type name.
     * @param string $type_namespace [optional] The type namespace.
     * @param string $node_name [optional] The XML node name.
     * @param string $node_namespace [optional] The XML node namespace.
     * @since 5.0
     * @removed 8.0
     */
    public function SoapVar($data, $encoding, $type_name = '', $type_namespace = '', $node_name = '', $node_namespace = '') {}
}
