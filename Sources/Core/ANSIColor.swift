public enum ANSIColor: String, CustomStringConvertible {
  case cyan = "\u{001B}[36m"
  case yellow = "\u{001B}[33m"
  case dim = "\u{001B}[2m"
  case bold = "\u{001B}[1m"
  case red = "\u{001B}[31m"
  case reset = "\u{001B}[0m"

  public var description: String { rawValue }
}
