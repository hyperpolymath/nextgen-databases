// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * PHP Code Generator
 *
 * Generates PHP client code from API specification
 */

open ApiSpec
open Generator

let name = "PHP"
let fileExtension = ".php"

/** Convert data type to PHP type hint */
let rec dataTypeToPhp = (dt: dataType): string =>
  switch dt {
  | String => "string"
  | Int => "int"
  | Float => "float"
  | Bool => "bool"
  | Array(inner) => `array`
  | Object(_) => "array"
  | Optional(inner) => `?${dataTypeToPhp(inner)}`
  | Enum(name, _) => capitalize(name)
  | Ref(name) => capitalize(name)
  }

/** Generate PHP enum */
let generatePhpEnum = (name: string, values: array<string>): string => {
  let cases = values
    ->Array.map(v => `    case ${String.toUpperCase(String.replaceAll(v, "-", "_"))} = '${v}';`)
    ->Array.joinWith("\n")

  `enum ${capitalize(name)}: string
{
${cases}
}`
}

/** Generate PHP class for a type */
let generatePhpClass = (name: string, fields: array<(string, dataType)>, desc: string): string => {
  let properties = fields
    ->Array.map(((fieldName, fieldType)) =>
      `        public readonly ${dataTypeToPhp(fieldType)} $${fieldName},`
    )
    ->Array.joinWith("\n")

  let fromArrayBody = fields
    ->Array.map(((fieldName, fieldType)) => {
      let accessor = `$data['${fieldName}']`
      switch fieldType {
      | Optional(_) => `            ${fieldName}: ${accessor} ?? null,`
      | Ref(refName) => `            ${fieldName}: ${capitalize(refName)}::fromArray(${accessor}),`
      | Enum(enumName, _) => `            ${fieldName}: ${capitalize(enumName)}::tryFrom(${accessor} ?? '') ?? ${capitalize(enumName)}::cases()[0],`
      | _ => `            ${fieldName}: ${accessor},`
      }
    })
    ->Array.joinWith("\n")

  `/**
 * ${desc}
 */
final class ${capitalize(name)}
{
    public function __construct(
${properties}
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
${fromArrayBody}
        );
    }
}`
}

/** Generate type definition */
let generateTypeDef = (typeDef: typeDef): string => {
  switch typeDef.dataType {
  | Enum(name, values) => generatePhpEnum(name, values)
  | Object(fields) => generatePhpClass(typeDef.name, fields, typeDef.description)
  | _ => ""
  }
}

/** Generate types file */
let generateTypesFile = (spec: apiSpec): generatedFile => {
  let header = `<?php

declare(strict_types=1);

// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Types
 *
 * Auto-generated from API specification v${spec.version}
 */

namespace Lith\\Types;

`

  let types = spec.types
    ->Array.map(generateTypeDef)
    ->Array.filter(s => String.length(s) > 0)
    ->Array.joinWith("\n\n")

  {
    path: "Types.php",
    content: header ++ types ++ "\n",
  }
}

/** Generate endpoint method */
let generateEndpointMethod = (endpoint: endpoint): string => {
  let methodStr = methodToString(endpoint.method)
  let returnType = dataTypeToPhp(endpoint.responseType)

  // Build parameter list
  let params = endpoint.parameters
    ->Array.map(p => {
      let typeHint = dataTypeToPhp(p.dataType)
      if p.required {
        `${typeHint} $${p.name}`
      } else {
        `?${typeHint} $${p.name} = null`
      }
    })
    ->Array.joinWith(", ")

  // Build path with substitutions
  let pathCode = if String.includes(endpoint.path, "{") {
    let pathParts = String.split(endpoint.path, "/")->Array.map(part => {
      if String.startsWith(part, "{") && String.endsWith(part, "}") {
        let varName = String.slice(part, ~start=1, ~end=String.length(part) - 1)
        `\" . $${varName} . \"`
      } else {
        part
      }
    })
    `\"${Array.joinWith(pathParts, "/")}\"`
  } else {
    `'${endpoint.path}'`
  }

  let bodyCode = switch endpoint.requestBody {
  | Some(_) => ", $body"
  | None => ""
  }

  `    /**
     * ${endpoint.description}
     */
    public function ${endpoint.name}(${params}): ${returnType}
    {
        $response = $this->request('${methodStr}', ${pathCode}${bodyCode});
        return ${capitalize(endpoint.name)}Result::fromArray($response);
    }`
}

/** Generate client file */
let generateClientFile = (spec: apiSpec): generatedFile => {
  let header = `<?php

declare(strict_types=1);

// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith PHP Client
 *
 * Auto-generated from API specification v${spec.version}
 */

namespace Lith;

use Lith\\Types\\*;
use Psr\\Http\\Client\\ClientInterface;
use Psr\\Http\\Message\\RequestFactoryInterface;
use Psr\\Http\\Message\\StreamFactoryInterface;

/**
 * Lith Exception
 */
class LithException extends \\Exception
{
    public function __construct(
        string $message,
        public readonly string $code = '',
        public readonly ?array $details = null,
        ?\\Throwable $previous = null
    ) {
        parent::__construct($message, 0, $previous);
    }
}

/**
 * Lith Client
 */
final class LithClient
{
    private string $baseUrl;
    private ?string $apiKey = null;
    private ?string $bearerToken = null;
    private ClientInterface $httpClient;
    private RequestFactoryInterface $requestFactory;
    private StreamFactoryInterface $streamFactory;

    public function __construct(
        string $baseUrl,
        ClientInterface $httpClient,
        RequestFactoryInterface $requestFactory,
        StreamFactoryInterface $streamFactory,
    ) {
        $this->baseUrl = rtrim($baseUrl, '/');
        $this->httpClient = $httpClient;
        $this->requestFactory = $requestFactory;
        $this->streamFactory = $streamFactory;
    }

    public static function fromEnv(
        ClientInterface $httpClient,
        RequestFactoryInterface $requestFactory,
        StreamFactoryInterface $streamFactory,
    ): self {
        $baseUrl = getenv('LITH_URL') ?: 'http://localhost:8080';
        $client = new self($baseUrl, $httpClient, $requestFactory, $streamFactory);
        if ($apiKey = getenv('LITH_API_KEY')) {
            $client->setApiKey($apiKey);
        }
        return $client;
    }

    public function setApiKey(string $apiKey): self
    {
        $this->apiKey = $apiKey;
        $this->bearerToken = null;
        return $this;
    }

    public function setBearerToken(string $token): self
    {
        $this->bearerToken = $token;
        $this->apiKey = null;
        return $this;
    }

    private function request(string $method, string $path, ?array $body = null): array
    {
        $url = $this->baseUrl . $path;
        $request = $this->requestFactory->createRequest($method, $url);

        $request = $request
            ->withHeader('Content-Type', 'application/json')
            ->withHeader('Accept', 'application/json');

        if ($this->apiKey !== null) {
            $request = $request->withHeader('X-API-Key', $this->apiKey);
        } elseif ($this->bearerToken !== null) {
            $request = $request->withHeader('Authorization', 'Bearer ' . $this->bearerToken);
        }

        if ($body !== null) {
            $jsonBody = json_encode($body, JSON_THROW_ON_ERROR);
            $stream = $this->streamFactory->createStream($jsonBody);
            $request = $request->withBody($stream);
        }

        $response = $this->httpClient->sendRequest($request);
        $statusCode = $response->getStatusCode();
        $responseBody = (string) $response->getBody();

        if ($statusCode >= 400) {
            $errorData = json_decode($responseBody, true) ?: [];
            throw new LithException(
                $errorData['message'] ?? 'Request failed',
                (string) $statusCode,
                $errorData['details'] ?? null
            );
        }

        if ($responseBody === '') {
            return [];
        }

        return json_decode($responseBody, true, 512, JSON_THROW_ON_ERROR);
    }

    // API Methods - see hand-crafted client for full implementation
}
`

  {
    path: "LithClient.php",
    content: header,
  }
}

/** Generate all files */
let generate = (spec: apiSpec): array<generatedFile> => {
  [
    generateTypesFile(spec),
    generateClientFile(spec),
  ]
}
