import AppKit
import SwiftUI

private final class LabAppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.setActivationPolicy(.regular)
		NSApp.activate(ignoringOtherApps: true)
	}
}

@main
struct SidebarResizeLabApp: App {
	@NSApplicationDelegateAdaptor(LabAppDelegate.self) private var appDelegate

	var body: some Scene {
		WindowGroup("Лаборатория сайдбара") {
			SidebarResizeLab()
		}
		.defaultSize(width: 1_180, height: 780)
	}
}

private enum ResizeStrategy: String, CaseIterable, Identifiable {
	case flexibleRows
	case boundedWidth
	case adaptiveAccessories
	case automaticCollapse
	case compactRail
	case fixedWidth
	case nativeList
	case overflowMenu
	case snapWidths

	var id: Self { self }

	var title: String {
		switch self {
		case .flexibleRows: "Эластичные строки"
		case .boundedWidth: "Ограниченная ширина"
		case .adaptiveAccessories: "Адаптивные индикаторы"
		case .automaticCollapse: "Автоматическое скрытие"
		case .compactRail: "Компактная полоса иконок"
		case .fixedWidth: "Фиксированный сайдбар"
		case .nativeList: "Системный список"
		case .overflowMenu: "Меню «Ещё»"
		case .snapWidths: "Две фиксируемые ширины"
		}
	}

	var score: Int {
		switch self {
		case .flexibleRows: 9
		case .boundedWidth: 9
		case .adaptiveAccessories: 8
		case .automaticCollapse: 8
		case .nativeList: 8
		case .snapWidths: 7
		case .overflowMenu: 6
		case .fixedWidth: 5
		case .compactRail: 4
		}
	}

	var status: String {
		switch self {
		case .flexibleRows, .boundedWidth: "Рекомендуется"
		case .adaptiveAccessories, .automaticCollapse, .nativeList: "Сильный вариант"
		case .snapWidths, .overflowMenu: "Зависит от сценария"
		case .fixedWidth: "Безопасный запасной вариант"
		case .compactRail: "Эксперимент"
		}
	}

	var summary: String {
		switch self {
		case .flexibleRows:
			"Строки занимают доступную ширину. Заголовок обрезается справа, а иконки остаются внутри колонки. Это устраняет причину обрезки."
		case .boundedWidth:
			"Сайдбар остаётся в диапазоне 200–300 пт. Разделитель останавливается до того, как навигация потеряет читаемость."
		case .adaptiveAccessories:
			"На малой ширине сначала исчезают счётчики и сочетание клавиш. Подписи и иконки сохраняются."
		case .automaticCollapse:
			"Если места не хватает, сайдбар скрывается целиком. Вернуть его можно кнопкой в панели инструментов или командой меню «Вид»."
		case .compactRail:
			"Ниже порога сайдбар превращается в полосу иконок шириной 56 пт. Она экономит место, но непривычна для дневника на Mac."
		case .fixedWidth:
			"Ширина сайдбара всегда равна 220 пт. Макет не ломается, но пользователь больше не может настроить колонку."
		case .nativeList:
			"Системный список в стиле сайдбара сам управляет выделением и сжатием строк. Собственного кода раскладки становится меньше."
		case .overflowMenu:
			"Основные разделы остаются на месте. На малой ширине архив и корзина переезжают в меню «Ещё»."
		case .snapWidths:
			"Разделитель фиксируется в компактном и обычном положениях. Макет предсказуем, но перетаскивание ощущается менее прямым."
		}
	}

	var tradeoff: String {
		switch self {
		case .flexibleRows: "Всё равно нужен разумный минимум ширины."
		case .boundedWidth: "Длинные названия дневников и тем обрезаются раньше."
		case .adaptiveAccessories: "Счётчики временно исчезают."
		case .automaticCollapse: "После скрытия навигация открывается отдельным действием."
		case .compactRail: "Одни иконки сложнее выучить, локализация им не помогает."
		case .fixedWidth: "Пропадает привычная для macOS настройка ширины."
		case .nativeList: "Придётся заменить собственные эффекты наведения и перетаскивания."
		case .overflowMenu: "Архив и корзину становится сложнее найти."
		case .snapWidths: "Во время перетаскивания разделитель может прыгать."
		}
	}
}

private struct SidebarResizeLab: View {
	@State private var strategy = ResizeStrategy.flexibleRows
	@State private var requestedWidth: CGFloat = 220
	@State private var requestedWindowWidth: CGFloat = 800
	@State private var dragStartWidth: CGFloat?

	var body: some View {
		NavigationSplitView {
			List(ResizeStrategy.allCases, selection: $strategy) { item in
				VStack(alignment: .leading, spacing: 3) {
					Text(item.title)
					Text("\(item.score)/10 · \(item.status)")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.tag(item)
				.padding(.vertical, 3)
			}
			.navigationTitle("Варианты")
			.navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 280)
		} detail: {
			VStack(spacing: 0) {
				inspector
				Divider()
				preview
			}
		}
		.navigationSplitViewStyle(.balanced)
	}

	private var inspector: some View {
		HStack(alignment: .top, spacing: 24) {
			VStack(alignment: .leading, spacing: 6) {
				HStack(spacing: 8) {
					Text(strategy.title)
						.font(.title2.weight(.semibold))
					Text(strategy.status)
						.font(.caption.weight(.medium))
						.padding(.horizontal, 8)
						.padding(.vertical, 3)
						.background(.quaternary, in: Capsule())
				}
				Text(strategy.summary)
					.foregroundStyle(.secondary)
				Text("Компромисс: \(strategy.tradeoff)")
					.font(.callout)
			}
			.frame(maxWidth: .infinity, alignment: .leading)

			VStack(alignment: .trailing, spacing: 8) {
				Text("Окно: \(Int(requestedWindowWidth)) пт")
					.monospacedDigit()
				Slider(value: $requestedWindowWidth, in: 520...1_000, step: 1)
					.frame(width: 240)
				Text("Сайдбар: \(Int(requestedWidth)) пт")
					.monospacedDigit()
				Slider(value: $requestedWidth, in: 120...360, step: 1)
					.frame(width: 240)
				Text("Сначала сузьте окно, затем потяните разделитель")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(20)
	}

	private var preview: some View {
		GeometryReader { proxy in
			let availableWidth = max(proxy.size.width - 48, 320)
			let metrics = LayoutMetrics(
				strategy: strategy,
				requestedWidth: requestedWidth,
				windowWidth: min(requestedWindowWidth, availableWidth)
			)

			VStack(spacing: 0) {
				FakeTitleBar(metrics: metrics)
				HStack(spacing: 0) {
					if !metrics.isCollapsed {
						SidebarSample(strategy: strategy, metrics: metrics)
							.frame(width: metrics.actualWidth)
							.clipped()
					}

					Divider()
						.frame(width: 7)
						.contentShape(.rect)
						.gesture(
							DragGesture(minimumDistance: 0)
								.onChanged { value in
									let start = dragStartWidth ?? requestedWidth
									dragStartWidth = start
									requestedWidth = min(max(start + value.translation.width, 120), 360)
								}
								.onEnded { _ in dragStartWidth = nil }
						)

					ContentSample(
						showsSidebarButton: metrics.isCollapsed,
						showsListColumn: metrics.showsListColumn,
						onShowSidebar: { requestedWidth = 220 }
					)
				}
			}
			.frame(width: metrics.windowWidth)
			.frame(maxHeight: .infinity)
			.background(Color(nsColor: .windowBackgroundColor))
			.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.stroke(Color(nsColor: .separatorColor), lineWidth: 1)
			}
			.shadow(color: .black.opacity(0.14), radius: 18, y: 8)
			.padding(24)
			.frame(maxWidth: .infinity)
			.accessibilityLabel("Предпросмотр сайдбара с изменяемой шириной")
			.onChange(of: proxy.size) { _, _ in
				requestedWidth = min(requestedWidth, 360)
			}
		}
	}
}

private struct LayoutMetrics {
	let strategy: ResizeStrategy
	let requestedWidth: CGFloat
	let windowWidth: CGFloat

	var actualWidth: CGFloat {
		switch strategy {
		case .boundedWidth: min(max(requestedWidth, 200), 300)
		case .fixedWidth: 220
		case .snapWidths: requestedWidth < 220 ? 184 : 260
		case .compactRail: requestedWidth < 176 ? 56 : requestedWidth
		default: requestedWidth
		}
	}

	var isCollapsed: Bool {
		strategy == .automaticCollapse && (requestedWidth < 176 || windowWidth < 700)
	}

	var isRail: Bool {
		strategy == .compactRail && requestedWidth < 176
	}

	var isNarrow: Bool { actualWidth < 205 }
	var showsAccessories: Bool { strategy != .adaptiveAccessories || actualWidth >= 205 }
	var usesOverflow: Bool { strategy == .overflowMenu && actualWidth < 205 }
	var showsListColumn: Bool { windowWidth >= 820 }
}

private struct FakeTitleBar: View {
	let metrics: LayoutMetrics

	var body: some View {
		HStack(spacing: 8) {
			Circle().fill(.red).frame(width: 12, height: 12)
			Circle().fill(.yellow).frame(width: 12, height: 12)
			Circle().fill(.green).frame(width: 12, height: 12)
			if !metrics.isCollapsed {
				Text("thingsdiary")
					.font(.headline)
					.frame(width: max(metrics.actualWidth - 84, 0), alignment: .trailing)
			}
			Divider().frame(height: 28)
			Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
			Text("Поиск")
				.foregroundStyle(.tertiary)
			Spacer()
		}
		.padding(.horizontal, 16)
		.frame(height: 52)
		.background(.bar)
	}
}

private struct SidebarSample: View {
	let strategy: ResizeStrategy
	let metrics: LayoutMetrics
	@State private var selection = "Корзина"
	@State private var topicsExpanded = true

	private let primaryRows = [
		("Новая запись", "square.and.pencil", "⌘N"),
		("Записи", "note.text", "4"),
		("Закладки", "bookmark", "1"),
	]

	var body: some View {
		Group {
			if strategy == .nativeList {
				nativeList
			} else if metrics.isRail {
				rail
			} else {
				customSidebar
			}
		}
		.background(.regularMaterial)
	}

	private var customSidebar: some View {
		VStack(spacing: 0) {
			diarySwitcher
			ScrollView {
				VStack(alignment: .leading, spacing: 4) {
					ForEach(primaryRows, id: \.0) { row in
						navigationRow(row.0, icon: row.1, accessory: row.2)
					}
					Divider().padding(.vertical, 4)
					topicsHeader
					if topicsExpanded {
						navigationRow("Долгосрочное исследование", icon: "tag", accessory: "")
						navigationRow("Демо", icon: "tag", accessory: "")
					}
					Divider().padding(.vertical, 4)
					if metrics.usesOverflow {
						navigationRow("Ещё", icon: "ellipsis.circle", accessory: "")
					} else {
						navigationRow("Архив", icon: "archivebox", accessory: "")
						navigationRow("Корзина", icon: "trash", accessory: "")
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(10)
			}
		}
	}

	private var diarySwitcher: some View {
		HStack(spacing: 8) {
			Image(systemName: "book.closed")
				.frame(width: 16)
			Text("Личный дневник")
				.lineLimit(1)
				.truncationMode(.tail)
				.layoutPriority(1)
			Spacer(minLength: 4)
			Image(systemName: "chevron.up.chevron.down")
				.font(.caption2.weight(.semibold))
		}
		.padding(.horizontal, 11)
		.frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
		.background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
		.padding(.init(top: 6, leading: 6, bottom: 2, trailing: 6))
	}

	private var topicsHeader: some View {
		Button {
			topicsExpanded.toggle()
		} label: {
			HStack(spacing: 8) {
				Image(systemName: "tag").frame(width: 16)
				Text("Темы").lineLimit(1)
				Spacer(minLength: 4)
				if metrics.showsAccessories {
					Image(systemName: topicsExpanded ? "chevron.down" : "chevron.right")
						.font(.caption)
				}
			}
			.padding(.horizontal, 7)
			.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
	}

	private func navigationRow(_ title: String, icon: String, accessory: String) -> some View {
		Button {
			selection = title
		} label: {
			HStack(spacing: 8) {
				Image(systemName: icon)
					.frame(width: 16)
					.foregroundStyle(.tint)
				Text(title)
					.lineLimit(1)
					.truncationMode(.tail)
					.layoutPriority(1)
				Spacer(minLength: 4)
				if metrics.showsAccessories, !accessory.isEmpty {
					Text(accessory)
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
						.fixedSize()
				}
			}
			.padding(.horizontal, 7)
			.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
			.contentShape(.rect)
			.background(
				selection == title ? Color.accentColor.opacity(0.18) : .clear,
				in: RoundedRectangle(cornerRadius: 7)
			)
		}
		.buttonStyle(.plain)
		.help(title)
	}

	private var nativeList: some View {
		List(selection: $selection) {
			Label("Новая запись", systemImage: "square.and.pencil").tag("Новая запись")
			Label("Записи", systemImage: "note.text").tag("Записи")
			Label("Закладки", systemImage: "bookmark").tag("Закладки")
			Section("Темы") {
				Label("Долгосрочное исследование", systemImage: "tag").tag("Долгосрочное исследование")
				Label("Демо", systemImage: "tag").tag("Демо")
			}
			Label("Архив", systemImage: "archivebox").tag("Архив")
			Label("Корзина", systemImage: "trash").tag("Корзина")
		}
		.listStyle(.sidebar)
	}

	private var rail: some View {
		VStack(spacing: 6) {
			ForEach(
				primaryRows + [("Темы", "tag", ""), ("Архив", "archivebox", ""), ("Корзина", "trash", "")], id: \.0
			) { row in
				Button {
					selection = row.0
				} label: {
					Image(systemName: row.1)
						.frame(width: 32, height: 30)
						.background(
							selection == row.0 ? Color.accentColor.opacity(0.18) : .clear,
							in: RoundedRectangle(cornerRadius: 7)
						)
				}
				.buttonStyle(.plain)
				.help(row.0)
			}
			Spacer()
		}
		.padding(.vertical, 8)
		.frame(maxWidth: .infinity)
	}
}

private struct ContentSample: View {
	let showsSidebarButton: Bool
	let showsListColumn: Bool
	let onShowSidebar: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				if showsSidebarButton {
					Button(action: onShowSidebar) {
						Image(systemName: "sidebar.left")
					}
					.buttonStyle(.borderless)
					.help("Показать сайдбар")
				}
				Text("Корзина")
					.font(.headline)
				Spacer()
			}
			.padding(.horizontal, 16)
			.frame(height: 44)
			Divider()
			HStack(spacing: 0) {
				if showsListColumn {
					VStack(alignment: .leading, spacing: 10) {
						Text("ЗАПИСИ").font(.caption).foregroundStyle(.secondary)
						ForEach(["Утренние заметки", "Набросок проекта", "Книги для чтения"], id: \.self) { title in
							Text(title).lineLimit(1)
						}
						Spacer()
					}
					.padding(16)
					.frame(width: 240, alignment: .topLeading)
					.frame(maxHeight: .infinity, alignment: .topLeading)
					Divider()
				}
				ContentUnavailableView {
					Label("Корзина пуста", systemImage: "trash")
				} description: {
					Text("Удалённые записи остаются здесь до окончательного удаления.")
						.lineLimit(2)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
		.background(Color(nsColor: .textBackgroundColor))
	}
}
