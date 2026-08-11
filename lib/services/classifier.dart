import '../domain/models.dart';

class SensitiveTextClassifier {
  static final _email = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final _phone = RegExp(
    r'(?<!\w)(?:\+?\d{1,3}[\s.-]?)?(?:\(?\d{2,4}\)?[\s.-]?)\d{3,4}[\s.-]?\d{4}(?!\w)',
  );
  static final _card = RegExp(r'(?<!\d)(?:\d[ -]?){13,19}(?!\d)');
  static final _url = RegExp(
    r'(?<![@\w])(?:(?:https?://|www\.)[^\s]+|[a-z0-9-]+(?:\.[a-z0-9-]+)+(?::\d+)?(?:/[^\s]*)?)',
    caseSensitive: false,
  );
  static final _addressLabel = RegExp(
    r'\b(?:address|billing\s+address|delivery\s+address|shipping\s+address|residential\s+address|location|current\s+location|based\s+in|located\s+in)\b\s*:?',
    caseSensitive: false,
  );
  static final _streetAddress = RegExp(
    r"\b(?:\d{1,6}[A-Z]?\s+)?(?:[A-Z0-9][A-Z0-9.'-]*\s+){0,7}(?:street|st|road|rd|avenue|ave|lane|ln|drive|dr|boulevard|blvd|court|ct|place|pl|terrace|trail|highway|hwy|way)\b(?:\s*[,#-]?\s*(?:apt|apartment|suite|unit|flat|floor)\s*[A-Z0-9-]+)?",
    caseSensitive: false,
  );
  static final _structuredAddress = RegExp(
    r'\b(?:house|flat|plot|apartment|apt|suite|unit|block|sector|phase|floor)\s*(?:no\.?\s*)?[A-Z0-9-]+',
    caseSensitive: false,
  );
  static final _poBox = RegExp(
    r'\bP\.?\s*O\.?\s+BOX\s+\d+\b',
    caseSensitive: false,
  );
  static final _postalLocation = RegExp(
    r"\b(?:[A-Z][A-Z .'-]+,\s*)?[A-Z]{2}\s+\d{5}(?:-\d{4})?\b|\b[A-Z]\d[A-Z]\s?\d[A-Z]\d\b|\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b",
    caseSensitive: false,
  );
  static final _cityLocation = RegExp(
    r"^\s*(?:islamabad|rawalpindi|lahore|karachi|peshawar|quetta|faisalabad|multan|sialkot|gujranwala|hyderabad|abu\s+dhabi|dubai|sharjah|ajman|al\s+ain|ras\s+al\s+khaimah|fujairah|umm\s+al\s+quwain|riyadh|jeddah|doha|muscat|manama|kuwait\s+city|cairo|amman|beirut|istanbul|london|paris|berlin|madrid|rome|amsterdam|brussels|vienna|zurich|geneva|stockholm|oslo|copenhagen|helsinki|dublin|lisbon|prague|warsaw|budapest|athens|singapore|tokyo|seoul|beijing|shanghai|hong\s+kong|bangkok|kuala\s+lumpur|jakarta|manila|new\s+delhi|delhi|mumbai|bengaluru|bangalore|toronto|vancouver|montreal|new\s+york|los\s+angeles|san\s+francisco|chicago|boston|seattle|austin|sydney|melbourne|brisbane|auckland|cape\s+town|johannesburg|nairobi)(?:\s*(?:,|[-–])\s*[a-z][a-z .'-]{1,40})?\s*$",
    caseSensitive: false,
  );
  static final _cardSecurityCodeLabel = RegExp(
    r'\b(?:CVV2?|CVC2?|CID|CSC|CARD\s+SECURITY\s+CODE|SECURITY\s+CODE)\b',
    caseSensitive: false,
  );
  static final _shortSecurityCode = RegExp(
    r'^\s*[^A-Z0-9]*\d{3,4}[^A-Z0-9]*\s*$',
    caseSensitive: false,
  );
  static final _expiryDate = RegExp(
    r'(?<!\d)(?:0?[1-9]|1[0-2])\s*[/\-]\s*\d{2,4}(?!\d)',
  );
  static final _validityLabel = RegExp(
    r'\b(?:VALID|VAL[I1]D|THRU|THROUGH|EXP|EXPIRES?|EXPIRY)\b',
    caseSensitive: false,
  );
  static final _possibleSecurityCode = RegExp(r'(?<!\d)\d{3,4}(?!\d)');

  RedactionCategory classify(String text) {
    if (_email.hasMatch(text)) return RedactionCategory.email;
    if (isCardSecurityCodeLabel(text) || isCardSecurityContext(text)) {
      return RedactionCategory.cardSecurityCode;
    }
    for (final match in _card.allMatches(text)) {
      final digits = match.group(0)!.replaceAll(RegExp(r'\D'), '');
      if ({13, 14, 15, 16, 17, 18, 19}.contains(digits.length) &&
          passesLuhn(digits)) {
        return RedactionCategory.card;
      }
    }
    if (_phone.hasMatch(text)) return RedactionCategory.phone;
    if (_url.hasMatch(text)) return RedactionCategory.url;
    if (isAddressLabel(text) || looksLikeAddressValue(text)) {
      return RedactionCategory.address;
    }
    return RedactionCategory.otherText;
  }

  bool isAddressLabel(String text) => _addressLabel.hasMatch(text);

  bool looksLikeAddressValue(String text) =>
      _streetAddress.hasMatch(text) ||
      _structuredAddress.hasMatch(text) ||
      _poBox.hasMatch(text) ||
      _postalLocation.hasMatch(text) ||
      looksLikeCityLocation(text);

  bool looksLikeCityLocation(String text) => _cityLocation.hasMatch(text);

  bool isCardSecurityCodeLabel(String text) {
    if (_cardSecurityCodeLabel.hasMatch(text)) return true;

    // Camera OCR commonly reads the final C/V in CVC or CVV as E, G, U, or Y.
    // A one-character OCR error must not expose a card security code.
    final words = text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
        .split(' ')
        .where((word) => word.isNotEmpty);
    for (var word in words) {
      if (word.endsWith('2') && word.length == 4) {
        word = word.substring(0, 3);
      }
      if (word.length == 3 &&
          (_oneEditOrLess(word, 'CVC') || _oneEditOrLess(word, 'CVV'))) {
        return true;
      }
    }
    return false;
  }

  bool isCardSecurityContext(String text) {
    final expiryCount = _expiryDate.allMatches(text).length;
    if (expiryCount == 0) return false;
    final hasTrailingCode = RegExp(r'(?<!\d)\d{3,4}[^\d]*$').hasMatch(text);
    return hasTrailingCode &&
        (_validityLabel.hasMatch(text) || expiryCount >= 2);
  }

  bool isShortSecurityCodeValue(String text) =>
      _shortSecurityCode.hasMatch(text);

  bool hasPossibleSecurityCodeValue(String text) =>
      _possibleSecurityCode.hasMatch(text);

  bool _oneEditOrLess(String value, String expected) {
    if (value == expected) return true;
    if (value.length != expected.length) return false;
    var differences = 0;
    for (var i = 0; i < value.length; i++) {
      if (value[i] != expected[i] && ++differences > 1) return false;
    }
    return true;
  }

  bool passesLuhn(String digits) {
    if (!RegExp(r'^\d+$').hasMatch(digits)) return false;
    var sum = 0;
    var doubleDigit = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var value = int.parse(digits[i]);
      if (doubleDigit) {
        value *= 2;
        if (value > 9) value -= 9;
      }
      sum += value;
      doubleDigit = !doubleDigit;
    }
    return sum % 10 == 0;
  }
}
