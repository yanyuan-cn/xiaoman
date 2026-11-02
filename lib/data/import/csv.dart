/// 极简 CSV 解析：支持双引号包裹、引号内转义（""）、逗号与换行。
List<List<String>> parseCsv(String input) {
  final List<List<String>> rows = <List<String>>[];
  List<String> row = <String>[];
  final StringBuffer buf = StringBuffer();
  bool inQuotes = false;

  for (int i = 0; i < input.length; i++) {
    final String ch = input[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buf.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      row.add(buf.toString());
      buf.clear();
    } else if (ch == '\n') {
      row.add(buf.toString());
      buf.clear();
      rows.add(row);
      row = <String>[];
    } else if (ch == '\r') {
      // 忽略
    } else {
      buf.write(ch);
    }
  }
  if (buf.isNotEmpty || row.isNotEmpty) {
    row.add(buf.toString());
    rows.add(row);
  }
  return rows;
}
