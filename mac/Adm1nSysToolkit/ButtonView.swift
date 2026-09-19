import SwiftUI

struct ButtonView: View {
  let title: String
  var body: some View { Text(title).frame(minWidth: 72) }
}
