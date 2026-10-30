import AppKit
import SwiftUI

/// Set `text` to update or clear the query, and `isFocused` to control keyboard focus.
/// The clear button and Escape clear a nonempty query while keeping focus.
/// Escape with an empty query releases focus.
struct SearchBox: View {
	@Binding var text: String
	@Binding var isFocused: Bool
	let prompt: String
	let accessibilityLabel: String
	let accessibilityIdentifier: String
	@State private var isHovered = false

	var body: some View {
		HStack(spacing: 8) {
			AppIconImage(icon: .search, size: 13)
				.font(.system(size: 13, weight: .medium))
				.foregroundStyle(.secondary)

			SearchTextField(
				text: $text,
				isFocused: $isFocused,
				prompt: prompt,
				accessibilityLabel: accessibilityLabel,
				accessibilityIdentifier: accessibilityIdentifier
			)
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			if !text.isEmpty {
				TabIconButton(icon: .circleX, iconSize: 13) {
					text = ""
					isFocused = true
				}
				.foregroundStyle(.secondary)
				.accessibilityLabel("Clear \(accessibilityLabel)")
				.help("Clear search")
			}
		}
		.padding(.leading, 11)
		.padding(.trailing, text.isEmpty ? 11 : 4)
		.frame(height: 34)
		.background {
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.fill(Color.primary.opacity(backgroundOpacity))
		}
		.overlay {
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.strokeBorder(
					isFocused ? Color.accentColor.opacity(0.85) : Color.clear,
					lineWidth: isFocused ? 2 : 1
				)
		}
		.contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
		.onTapGesture { isFocused = true }
		.onHover { isHovered = $0 }
		.animation(.easeOut(duration: 0.14), value: isFocused)
		.animation(.easeOut(duration: 0.14), value: isHovered)
	}

	private var backgroundOpacity: Double {
		if isFocused { return 0.075 }
		return isHovered ? 0.06 : 0.045
	}
}

private final class EscapeHandlingSearchField: NSSearchField {
	var escapeHandler: (() -> Void)?

	override func cancelOperation(_ sender: Any?) {
		escapeHandler?()
	}
}

private struct SearchTextField: NSViewRepresentable {
	@Binding var text: String
	@Binding var isFocused: Bool
	let prompt: String
	let accessibilityLabel: String
	let accessibilityIdentifier: String

	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	func makeNSView(context: Context) -> EscapeHandlingSearchField {
		let field = EscapeHandlingSearchField()
		field.delegate = context.coordinator
		field.placeholderString = prompt
		field.sendsSearchStringImmediately = true
		field.target = context.coordinator
		field.action = #selector(Coordinator.searchFieldAction(_:))
		field.isBezeled = false
		field.isBordered = false
		field.drawsBackground = false
		field.focusRingType = .none
		field.font = .systemFont(ofSize: NSFont.systemFontSize)
		field.setAccessibilityIdentifier(accessibilityIdentifier)
		field.setAccessibilityLabel(accessibilityLabel)
		if let searchCell = field.cell as? NSSearchFieldCell {
			searchCell.searchButtonCell = nil
			searchCell.cancelButtonCell = nil
		}
		field.escapeHandler = { [weak field, weak coordinator = context.coordinator] in
			guard let field, let coordinator else { return }
			coordinator.handleEscape(in: field)
		}
		return field
	}

	func updateNSView(_ field: EscapeHandlingSearchField, context: Context) {
		context.coordinator.parent = self
		field.placeholderString = prompt
		field.setAccessibilityIdentifier(accessibilityIdentifier)
		field.setAccessibilityLabel(accessibilityLabel)
		context.coordinator.applyTextIfNeeded(to: field)

		if isFocused {
			guard field.currentEditor() == nil else { return }
			DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
		} else if field.currentEditor() != nil {
			DispatchQueue.main.async { field.window?.makeFirstResponder(nil) }
		}
	}

	final class Coordinator: NSObject, NSSearchFieldDelegate {
		var parent: SearchTextField

		init(_ parent: SearchTextField) {
			self.parent = parent
		}

		func controlTextDidBeginEditing(_ notification: Notification) {
			parent.isFocused = true
		}

		func controlTextDidEndEditing(_ notification: Notification) {
			if let field = notification.object as? NSSearchField {
				parent.text = field.stringValue
			}
			parent.isFocused = false
		}

		func controlTextDidChange(_ notification: Notification) {
			guard let field = notification.object as? NSSearchField else { return }
			parent.isFocused = true
			parent.text = field.stringValue
		}

		func control(
			_ control: NSControl,
			textView: NSTextView,
			doCommandBy commandSelector: Selector
		) -> Bool {
			guard
				commandSelector == #selector(NSResponder.cancelOperation(_:)),
				let field = control as? NSSearchField
			else { return false }
			handleEscape(in: field)
			return true
		}

		@objc func searchFieldAction(_ field: NSSearchField) {
			parent.text = field.stringValue
		}

		func handleEscape(in field: NSSearchField) {
			if field.stringValue.isEmpty {
				parent.isFocused = false
				field.window?.makeFirstResponder(nil)
			} else {
				field.stringValue = ""
				field.currentEditor()?.string = ""
				parent.text = ""
				parent.isFocused = true
			}
		}

		func applyTextIfNeeded(to field: NSSearchField) {
			guard field.stringValue != parent.text else { return }
			field.stringValue = parent.text
			guard let editor = field.currentEditor() as? NSTextView else { return }
			editor.string = parent.text
			editor.setSelectedRange(NSRange(location: (parent.text as NSString).length, length: 0))
		}
	}
}
