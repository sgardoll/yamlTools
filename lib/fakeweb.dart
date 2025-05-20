// This is a stub implementation to support conditional imports
// It's never actually used in non-web contexts

class Blob {
  Blob(List<dynamic> data, String type) {}
}

class Url {
  static String createObjectUrlFromBlob(Blob blob) => '';
  static void revokeObjectUrl(String url) {}
}

class AnchorElement {
  AnchorElement({String? href}) {}

  void setAttribute(String name, String value) {}
  void click() {}

  String style = '';
}

class Document {
  final DomList body = DomList();
}

class DomList {
  void add(dynamic element) {}
  void remove(dynamic element) {}

  final List<dynamic> children = [];
}

final Document document = Document();
