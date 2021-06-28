import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/src/model/csr/CertificateSigningRequestData.dart';
import 'package:basic_utils/src/model/csr/SubjectPublicKeyInfo.dart';
import 'package:basic_utils/src/model/pkcs7/Pkcs7CertificateData.dart';
import 'package:basic_utils/src/model/x509/X509CertificateData.dart';
import 'package:basic_utils/src/model/x509/X509CertificatePublicKeyData.dart';
import 'package:basic_utils/src/model/x509/X509CertificateValidity.dart';

import 'package:pointycastle/export.dart';
import 'package:pointycastle/pointycastle.dart';

import '../basic_utils.dart';

///
/// Helper class for certificate operations.
///
class X509Utils {
  static const BEGIN_PRIVATE_KEY = '-----BEGIN PRIVATE KEY-----';
  static const END_PRIVATE_KEY = '-----END PRIVATE KEY-----';

  static const BEGIN_PUBLIC_KEY = '-----BEGIN PUBLIC KEY-----';
  static const END_PUBLIC_KEY = '-----END PUBLIC KEY-----';

  static const BEGIN_CSR = '-----BEGIN CERTIFICATE REQUEST-----';
  static const END_CSR = '-----END CERTIFICATE REQUEST-----';

  static const BEGIN_EC_PRIVATE_KEY = '-----BEGIN EC PRIVATE KEY-----';
  static const END_EC_PRIVATE_KEY = '-----END EC PRIVATE KEY-----';

  static const BEGIN_EC_PUBLIC_KEY = '-----BEGIN EC PUBLIC KEY-----';
  static const END_EC_PUBLIC_KEY = '-----END EC PUBLIC KEY-----';

  static const DN = {
    'cn': '2.5.4.3',
    'sn': '2.5.4.4',
    'c': '2.5.4.6',
    'l': '2.5.4.7',
    'st': '2.5.4.8',
    's': '2.5.4.8',
    'o': '2.5.4.10',
    'ou': '2.5.4.11',
    'title': '2.5.4.12',
    'registeredAddress': '2.5.4.26',
    'member': '2.5.4.31',
    'owner': '2.5.4.32',
    'roleOccupant': '2.5.4.33',
    'seeAlso': '2.5.4.34',
    'givenName': '2.5.4.42',
    'initials': '2.5.4.43',
    'generationQualifier': '2.5.4.44',
    'dmdName': '2.5.4.54',
    'alias': '2.5.6.1',
    'country': '2.5.6.2',
    'locality': '2.5.6.3',
    'organization': '2.5.6.4',
    'organizationalUnit': '2.5.6.5',
    'person': '2.5.6.6',
    'organizationalPerson': '2.5.6.7',
    'organizationalRole': '2.5.6.8',
    'groupOfNames': '2.5.6.9',
    'residentialPerson': '2.5.6.10',
    'applicationProcess': '2.5.6.11',
    'applicationEntity': '2.5.6.12',
    'dSA': '2.5.6.13',
    'device': '2.5.6.14',
    'strongAuthenticationUser': '2.5.6.15',
    'certificationAuthority': '2.5.6.16',
    'groupOfUniqueNames': '2.5.6.17',
    'userSecurityInformation': '2.5.6.18',
    'certificationAuthority-V2': '2.5.6.16.2',
    'cRLDistributionPoint': '2.5.6.19',
    'dmd': '2.5.6.20',
    'md5WithRSAEncryption': '1.2.840.113549.1.1.4',
    'rsaEncryption': '1.2.840.113549.1.1.1',
    'organizationalUnitName': '2.5.4.11',
    'organizationName': '2.5.4.10',
    'stateOrProvinceName': '2.5.4.8',
    'commonName': '2.5.4.3',
    'surname': '2.5.4.4',
    'countryName': '2.5.4.6',
    'localityName': '2.5.4.7',
    'streetAddress': '2.5.4.9'
  };

  ///
  /// Formats the given [key] by chunking the [key] and adding the [begin] and [end] to the [key].
  ///
  /// The line length will be defined by the given [chunkSize]. The default value is 64.
  ///
  /// Each line will be delimited by the given [lineDelimiter]. The default value is '\n'.w
  ///
  static String formatKeyString(String key, String begin, String end,
      {int chunkSize = 64, String lineDelimiter = '\n'}) {
    var sb = StringBuffer();
    var chunks = StringUtils.chunk(key, chunkSize);
    sb.write(begin + lineDelimiter);
    for (var s in chunks) {
      sb.write(s + lineDelimiter);
    }
    sb.write(end);
    return sb.toString();
  }

  ///
  /// Generates a Certificate Signing Request with the given [attributes] using the given [privateKey] and [publicKey].
  ///
  static String generateRsaCsrPem(Map<String, String> attributes,
      RSAPrivateKey privateKey, RSAPublicKey publicKey) {
    var encodedDN = encodeDN(attributes);

    var blockDN = ASN1Sequence();
    blockDN.add(ASN1Integer(BigInt.from(0)));
    blockDN.add(encodedDN);
    blockDN.add(_makePublicKeyBlock(publicKey));
    blockDN.add(ASN1Null(tag: 0xA0)); // let's call this WTF

    var blockProtocol = ASN1Sequence();
    blockProtocol.add(ASN1ObjectIdentifier.fromName('sha256WithRSAEncryption'));
    blockProtocol.add(ASN1Null());

    var outer = ASN1Sequence();
    outer.add(blockDN);
    outer.add(blockProtocol);
    outer.add(
        ASN1BitString(stringValues: _rsaSign(blockDN.encode(), privateKey)));
    var chunks = StringUtils.chunk(base64.encode(outer.encode()), 64);
    return '$BEGIN_CSR\n${chunks.join('\r\n')}\n$END_CSR';
  }

  static Uint8List _rsaSign(Uint8List inBytes, RSAPrivateKey privateKey) {
    var signer = Signer('SHA-256/RSA');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

    var signature = signer.generateSignature(inBytes) as RSASignature;

    return signature.bytes;
  }

  ///
  /// Generates a eliptic curve Certificate Signing Request with the given [attributes] using the given [privateKey] and [publicKey].
  ///
  /// The CSR will be signed with algorithm **SHA-256/ECDSA**.
  ///
  static String generateEccCsrPem(Map<String, String> attributes,
      ECPrivateKey privateKey, ECPublicKey publicKey) {
    var encodedDN = encodeDN(attributes);
    var publicKeySequence = _makeEccPublicKeyBlock(publicKey);

    var blockDN = ASN1Sequence();
    blockDN.add(ASN1Integer(BigInt.from(0)));
    blockDN.add(encodedDN);
    blockDN.add(publicKeySequence);
    blockDN.add(ASN1Null(tag: 0xA0)); // let's call this WTF

    var blockSignatureAlgorithm = ASN1Sequence();
    blockSignatureAlgorithm
        .add(ASN1ObjectIdentifier.fromName('ecdsaWithSHA256'));

    var ecSignature = eccSign(blockDN.encode(), privateKey);

    var bitStringSequence = ASN1Sequence();
    bitStringSequence.add(ASN1Integer(ecSignature.r));
    bitStringSequence.add(ASN1Integer(ecSignature.s));
    var blockSignatureValue =
        ASN1BitString(stringValues: bitStringSequence.encode());

    var outer = ASN1Sequence();
    outer.add(blockDN);
    outer.add(blockSignatureAlgorithm);
    outer.add(blockSignatureValue);
    var chunks = StringUtils.chunk(base64.encode(outer.encode()), 64);
    return '$BEGIN_CSR\n${chunks.join('\r\n')}\n$END_CSR';
  }

  static ECSignature eccSign(Uint8List inBytes, ECPrivateKey privateKey) {
    var signer = Signer('SHA-256/ECDSA');
    //var signer = ECDSASigner();
    var privParams = PrivateKeyParameter<ECPrivateKey>(privateKey);
    var signParams = ParametersWithRandom(
      privParams,
      _getSecureRandom(),
    );
    signer.init(true, signParams);

    return signer.generateSignature(inBytes) as ECSignature;
  }

  static SecureRandom _getSecureRandom() {
    var secureRandom = FortunaRandom();
    var random = Random.secure();
    var seeds = <int>[];
    for (var i = 0; i < 32; i++) {
      seeds.add(random.nextInt(255));
    }
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  ///
  /// Encode the given [asn1Object] to PEM format and adding the [begin] and [end].
  ///
  static String encodeASN1ObjectToPem(
      ASN1Object asn1Object, String begin, String end) {
    var bytes = asn1Object.encode();
    var chunks = StringUtils.chunk(base64.encode(bytes), 64);
    return '$begin\n${chunks.join('\r\n')}\n$end';
  }

  ///
  /// Parses the given PEM
  ///
  static Pkcs7CertificateData pkcs7fromPem(String pem) {
    var bytes = CryptoUtils.getBytesFromPEMString(pem);
    var asn1Parser = ASN1Parser(bytes);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    var x509List = <X509CertificateData>[];
    var version = 0;
    var type = '';
    if (topLevelSeq.elements != null) {
      var oi = topLevelSeq.elements!.elementAt(0) as ASN1ObjectIdentifier;
      type = oi.objectIdentifierAsString!;
      var obj = topLevelSeq.elements!.elementAt(1);
      var seq = ASN1Sequence.fromBytes(obj.valueBytes!);
      var integer = seq.elements!.elementAt(0) as ASN1Integer;
      version = integer.integer!.toInt();
      var obj1 = seq.elements!.elementAt(3);
      var seq1 = ASN1Sequence.fromBytes(obj1.encodedBytes!);

      for (var el in seq1.elements!) {
        var x509 = _x509FromAsn1Sequence(el as ASN1Sequence);
        x509List.add(x509);
      }
    }

    return Pkcs7CertificateData(
        certificates: x509List, version: version, contentType: type);
  }

  static X509CertificateData _x509FromAsn1Sequence(ASN1Sequence topLevelSeq) {
    var dataSequence = topLevelSeq.elements!.elementAt(0) as ASN1Sequence;
    int version;
    var element = 0;
    var serialInteger;
    if (dataSequence.elements!.elementAt(0) is ASN1Integer) {
      // The version ASN1Object ist missing use version
      version = 1;
      // Serialnumber
      serialInteger = dataSequence.elements!.elementAt(element) as ASN1Integer;
      element = -1;
    } else {
      // Version
      var versionObject = dataSequence.elements!.elementAt(element + 0);
      version = versionObject.valueBytes!.elementAt(2);
      // Serialnumber
      serialInteger =
          dataSequence.elements!.elementAt(element + 1) as ASN1Integer;
    }
    BigInt serialNumber = serialInteger.integer;

    // Signature
    var signatureSequence =
        dataSequence.elements!.elementAt(element + 2) as ASN1Sequence;
    var o = signatureSequence.elements!.elementAt(0) as ASN1ObjectIdentifier;
    var signatureAlgorithm = o.objectIdentifierAsString!;

    // Issuer
    var issuerSequence =
        dataSequence.elements!.elementAt(element + 3) as ASN1Sequence;
    var issuer = <String, String?>{};
    for (var s in issuerSequence.elements as dynamic) {
      var setSequence = s.elements!.elementAt(0) as ASN1Sequence;
      var o = setSequence.elements!.elementAt(0) as ASN1ObjectIdentifier;
      var object = setSequence.elements!.elementAt(1);
      String? value = '';
      if (object is ASN1UTF8String) {
        var objectAsUtf8 = object;
        value = objectAsUtf8.utf8StringValue;
      } else if (object is ASN1PrintableString) {
        var objectPrintable = object;
        value = objectPrintable.stringValue;
      } else if (object is ASN1TeletextString) {
        var objectTeletext = object;
        value = objectTeletext.stringValue;
      }
      issuer.putIfAbsent(o.objectIdentifierAsString!, () => value);
    }

    // Validity
    var validitySequence =
        dataSequence.elements!.elementAt(element + 4) as ASN1Sequence;
    var asn1FromDateTime;
    var asn1ToDateTime;
    if (validitySequence.elements!.elementAt(0) is ASN1UtcTime) {
      var asn1From = validitySequence.elements!.elementAt(0) as ASN1UtcTime;
      asn1FromDateTime = asn1From.time;
    } else {
      var asn1From =
          validitySequence.elements!.elementAt(0) as ASN1GeneralizedTime;
      asn1FromDateTime = asn1From.dateTimeValue;
    }
    if (validitySequence.elements!.elementAt(1) is ASN1UtcTime) {
      var asn1To = validitySequence.elements!.elementAt(1) as ASN1UtcTime;
      asn1ToDateTime = asn1To.time;
    } else {
      var asn1To =
          validitySequence.elements!.elementAt(1) as ASN1GeneralizedTime;
      asn1ToDateTime = asn1To.dateTimeValue;
    }

    var validity = X509CertificateValidity(
        notBefore: asn1FromDateTime, notAfter: asn1ToDateTime);

    // Subject
    var subjectSequence =
        dataSequence.elements!.elementAt(element + 5) as ASN1Sequence;
    var subject = <String, String?>{};
    for (var s in subjectSequence.elements as dynamic) {
      var setSequence = s.elements!.elementAt(0) as ASN1Sequence;
      var o = setSequence.elements!.elementAt(0) as ASN1ObjectIdentifier;
      var object = setSequence.elements!.elementAt(1);
      String? value = '';
      if (object is ASN1UTF8String) {
        var objectAsUtf8 = object;
        value = objectAsUtf8.utf8StringValue;
      } else if (object is ASN1PrintableString) {
        var objectPrintable = object;
        value = objectPrintable.stringValue;
      }
      var identifier = o.objectIdentifierAsString ?? 'unknown';
      subject.putIfAbsent(identifier, () => value);
    }

    // Public Key
    var pubKeySequence =
        dataSequence.elements!.elementAt(element + 6) as ASN1Sequence;

    var algoSequence = pubKeySequence.elements!.elementAt(0) as ASN1Sequence;
    var pubKeyOid = algoSequence.elements!.elementAt(0) as ASN1ObjectIdentifier;

    var pubKey = pubKeySequence.elements!.elementAt(1) as ASN1BitString;
    var asn1PubKeyParser = ASN1Parser(pubKey.stringValues as Uint8List?);
    var next;
    try {
      next = asn1PubKeyParser.nextObject();
    } catch (e) {
      // continue
    }
    var pubKeyLength = 0;

    Uint8List? pubKeyAsBytes;

    if (next != null && next is ASN1Sequence) {
      var s = next;
      var key = s.elements!.elementAt(0) as ASN1Integer;
      pubKeyLength = key.integer!.bitLength;
      pubKeyAsBytes = s.encodedBytes;
    } else {
      pubKeyAsBytes = pubKey.valueBytes;
      pubKeyLength = pubKey.valueBytes!.length * 8;
    }
    var pubKeyThumbprint =
        CryptoUtils.getSha1ThumbprintFromBytes(pubKeySequence.encodedBytes!);
    var pubKeySha256Thumbprint =
        CryptoUtils.getSha256ThumbprintFromBytes(pubKeySequence.encodedBytes!);
    var publicKeyData = X509CertificatePublicKeyData(
        algorithm: pubKeyOid.objectIdentifierAsString,
        bytes: _bytesAsString(pubKeyAsBytes!),
        length: pubKeyLength,
        sha1Thumbprint: pubKeyThumbprint,
        sha256Thumbprint: pubKeySha256Thumbprint);
    List<String>? sans;
    if (version > 1) {
      // Extensions
      if (dataSequence.elements!.length == 8) {
        var extensionObject = dataSequence.elements!.elementAt(element + 7);
        var extParser = ASN1Parser(extensionObject.valueBytes);
        var extSequence = extParser.nextObject() as ASN1Sequence;

        extSequence.elements!.forEach((ASN1Object subseq) {
          var seq = subseq as ASN1Sequence;
          var oi = seq.elements!.elementAt(0) as ASN1ObjectIdentifier;
          if (oi.objectIdentifierAsString == '2.5.29.17') {
            if (seq.elements!.length == 3) {
              sans = _fetchSansFromExtension(seq.elements!.elementAt(2));
            } else {
              sans = _fetchSansFromExtension(seq.elements!.elementAt(1));
            }
          }
        });
      }
    }

    return X509CertificateData(
      version: version,
      serialNumber: serialNumber,
      signatureAlgorithm: signatureAlgorithm,
      issuer: issuer,
      validity: validity,
      subject: subject,
      publicKeyData: publicKeyData,
      subjectAlternativNames: sans,
    );
  }

  ///
  /// Parses the given PEM to a [X509CertificateData] object.
  ///
  /// Throws an [ASN1Exception] if the pem could not be read by the [ASN1Parser].
  ///
  static X509CertificateData x509CertificateFromPem(String pem) {
    var bytes = CryptoUtils.getBytesFromPEMString(pem);
    var asn1Parser = ASN1Parser(bytes);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    var x509 = _x509FromAsn1Sequence(topLevelSeq);

    var sha1String = CryptoUtils.getSha1ThumbprintFromBytes(bytes);
    var md5String = CryptoUtils.getMd5ThumbprintFromBytes(bytes);
    var sha256String = CryptoUtils.getSha256ThumbprintFromBytes(bytes);

    x509.plain = pem;
    x509.sha1Thumbprint = sha1String;
    x509.md5Thumbprint = md5String;
    x509.sha256Thumbprint = sha256String;
    return x509;
  }

  ///
  /// Decode the given [asnSequence] into an [RSAPrivateKey].
  ///
  static RSAPrivateKey privateKeyFromASN1Sequence(ASN1Sequence asnSequence) {
    var objects = asnSequence.elements!;

    var asnIntegers = objects.take(9).map((o) => o as ASN1Integer).toList();

    var version = asnIntegers.first;
    if (version.integer != BigInt.zero) {
      throw ArgumentError('Expected version 0, got: ${version.integer}.');
    }

    var key = RSAPrivateKey(asnIntegers[1].integer!, asnIntegers[2].integer!,
        asnIntegers[4].integer, asnIntegers[5].integer);

    var bitLength = key.n!.bitLength;
    if (bitLength != 1024 && bitLength != 2048 && bitLength != 4096) {
      throw ArgumentError('The RSA modulus has a bit length of $bitLength. '
          'Only 1024, 2048 and 4096 are supported.');
    }
    return key;
  }

  ///
  /// Encode the given [dn] (Distinguished Name) to a [ASN1Object].
  ///
  /// For supported DN see the rf at <https://tools.ietf.org/html/rfc2256>
  ///
  static ASN1Object encodeDN(Map<String, String> dn) {
    var distinguishedName = ASN1Sequence();
    dn.forEach((name, value) {
      var oid = ASN1ObjectIdentifier.fromName(name);

      ASN1Object ovalue;
      switch (name.toUpperCase()) {
        case 'C':
          ovalue = ASN1PrintableString(stringValue: value);
          break;
        case 'CN':
        case 'O':
        case 'L':
        case 'S':
        default:
          ovalue = ASN1UTF8String(utf8StringValue: value);
          break;
      }

      var pair = ASN1Sequence();
      pair.add(oid);
      pair.add(ovalue);

      var pairset = ASN1Set();
      pairset.add(pair);

      distinguishedName.add(pairset);
    });

    return distinguishedName;
  }

  ///
  /// Create  the public key ASN1Sequence for the csr.
  ///
  static ASN1Sequence _makePublicKeyBlock(RSAPublicKey publicKey) {
    var blockEncryptionType = ASN1Sequence();
    blockEncryptionType.add(ASN1ObjectIdentifier.fromName('rsaEncryption'));
    blockEncryptionType.add(ASN1Null());

    var publicKeySequence = ASN1Sequence();
    publicKeySequence.add(ASN1Integer(publicKey.modulus));
    publicKeySequence.add(ASN1Integer(publicKey.exponent));

    var blockPublicKey =
        ASN1BitString(stringValues: publicKeySequence.encode());

    var outer = ASN1Sequence();
    outer.add(blockEncryptionType);
    outer.add(blockPublicKey);

    return outer;
  }

  ///
  /// Create  the public key ASN1Sequence for the ECC csr.
  ///
  static ASN1Sequence _makeEccPublicKeyBlock(ECPublicKey publicKey) {
    var algorithm = ASN1Sequence();
    algorithm.add(ASN1ObjectIdentifier.fromName('ecPublicKey'));
    algorithm
        .add(ASN1ObjectIdentifier.fromName(publicKey.parameters!.domainName));

    var subjectPublicKey =
        ASN1BitString(stringValues: publicKey.Q!.getEncoded(false));

    var outer = ASN1Sequence();
    outer.add(algorithm);
    outer.add(subjectPublicKey);

    return outer;
  }

  ///
  /// Fetches a list of subject alternative names from the given [extData]
  ///
  static List<String> _fetchSansFromExtension(ASN1Object extData) {
    var sans = <String>[];
    var octet = extData as ASN1OctetString;
    var sanParser = ASN1Parser(octet.valueBytes);
    var sanSeq = sanParser.nextObject() as ASN1Sequence;
    sanSeq.elements!.forEach((ASN1Object san) {
      if (san.tag == 135) {
        var sb = StringBuffer();
        san.valueBytes!.forEach((int b) {
          if (sb.isNotEmpty) {
            sb.write('.');
          }
          sb.write(b);
        });
        sans.add(sb.toString());
      } else {
        var s = String.fromCharCodes(san.valueBytes!);
        sans.add(s);
      }
    });
    return sans;
  }

  ///
  /// Converts the bytes to a hex string
  ///
  static String _bytesAsString(Uint8List bytes) {
    var b = StringBuffer();
    bytes.forEach((v) {
      var s = v.toRadixString(16);
      if (s.length == 1) {
        b.write('0$s');
      } else {
        b.write(s);
      }
    });
    return b.toString().toUpperCase();
  }

  static CertificateSigningRequestData csrFromPem(String pem) {
    var bytes = CryptoUtils.getBytesFromPEMString(pem);
    var asn1Parser = ASN1Parser(bytes);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    var infoSeq = topLevelSeq.elements!.elementAt(0) as ASN1Sequence;
    var sigSeq = topLevelSeq.elements!.elementAt(1) as ASN1Sequence;
    var sig = topLevelSeq.elements!.elementAt(2) as ASN1BitString;

    // Get version
    var asn1Version = infoSeq.elements!.elementAt(0) as ASN1Integer;

    // Get Subject
    var subjectSequence = infoSeq.elements!.elementAt(1) as ASN1Sequence;
    var subject = <String, String>{};
    for (var s in subjectSequence.elements as dynamic) {
      var setSequence = s.elements!.elementAt(0) as ASN1Sequence;
      var o = setSequence.elements!.elementAt(0) as ASN1ObjectIdentifier;
      var object = setSequence.elements!.elementAt(1);
      String? value = '';
      if (object is ASN1UTF8String) {
        var objectAsUtf8 = object;
        value = objectAsUtf8.utf8StringValue;
      } else if (object is ASN1PrintableString) {
        var objectPrintable = object;
        value = objectPrintable.stringValue;
      }
      var identifier = o.objectIdentifierAsString ?? 'unknown';
      subject.putIfAbsent(identifier, () => value!);
    }

    // Get Public Key Data
    var pubSeq = infoSeq.elements!.elementAt(2) as ASN1Sequence;
    var algSeq = pubSeq.elements!.elementAt(0) as ASN1Sequence;
    var algOi = algSeq.elements!.elementAt(0) as ASN1ObjectIdentifier;
    var asn1AlgParameters = algSeq.elements!.elementAt(1);
    var algParameters = '';
    var algParametersReadable = '';
    if (asn1AlgParameters is ASN1ObjectIdentifier) {
      algParameters = asn1AlgParameters.objectIdentifierAsString!;
      algParametersReadable = asn1AlgParameters.readableName!;
    }

    var pubBitString = pubSeq.elements!.elementAt(1) as ASN1BitString;
    var asn1PubKeyParser = ASN1Parser(pubBitString.stringValues as Uint8List?);
    var next;
    try {
      next = asn1PubKeyParser.nextObject();
    } catch (e) {
      // continue
    }
    int pubKeyLength;
    Uint8List? pubKeyAsBytes;
    if (next != null && next is ASN1Sequence) {
      var s = next;
      var key = s.elements!.elementAt(0) as ASN1Integer;
      pubKeyLength = key.integer!.bitLength;
      pubKeyAsBytes = s.encodedBytes;
    } else {
      pubKeyAsBytes = pubBitString.valueBytes;
      pubKeyLength = pubBitString.valueBytes!.length * 8;
    }

    var pubKeyThumbprint =
        CryptoUtils.getHash(pubSeq.encodedBytes!, algorithmName: 'SHA-1');
    var pubKeySha256Thumbprint =
        CryptoUtils.getHash(pubSeq.encodedBytes!, algorithmName: 'SHA-256');

    var pubInfo = SubjectPublicKeyInfo(
      algorithm: algOi.objectIdentifierAsString,
      algorithmReadableName: algOi.readableName,
      parameter: algParameters != '' ? algParameters : null,
      parameterReadableName:
          algParametersReadable != '' ? algParametersReadable : null,
      length: pubKeyLength,
      bytes: _bytesAsString(pubKeyAsBytes!),
      sha1Thumbprint: pubKeyThumbprint,
      sha256Thumbprint: pubKeySha256Thumbprint,
    );

    // Get Signature Algorithm
    var pubKeyOid = sigSeq.elements!.elementAt(0) as ASN1ObjectIdentifier;

    // Get Signature
    var sigAsString = _bytesAsString(sig.valueBytes!);

    return CertificateSigningRequestData(
      version: asn1Version.integer!.toInt(),
      subject: subject,
      signatureAlgorithm: pubKeyOid.objectIdentifierAsString,
      signatureAlgorithmReadableName: pubKeyOid.readableName,
      signature: sigAsString,
      publicKeyInfo: pubInfo,
    );
  }
}
