import AppKit
import SwiftUI

private final class LabAppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.setActivationPolicy(.regular)
		NSApp.activate(ignoringOtherApps: true)
	}
}

@main
struct ListAnimationLabApp: App {
	@NSApplicationDelegateAdaptor(LabAppDelegate.self) private var appDelegate

	var body: some Scene {
		WindowGroup("Анимации списка") {
			ListAnimationLab()
		}
		.defaultSize(width: 1_340, height: 900)
	}
}

private enum ItemKind: String, CaseIterable, Identifiable {
	case entry
	case bookmark
	case archive
	case trash
	case template

	var id: Self { self }

	var title: String {
		switch self {
		case .entry: "Записи"
		case .bookmark: "Закладки"
		case .archive: "Архив"
		case .trash: "Корзина"
		case .template: "Темплейты"
		}
	}

	var systemImage: String {
		switch self {
		case .entry: "note.text"
		case .bookmark: "bookmark.fill"
		case .archive: "archivebox"
		case .trash: "trash"
		case .template: "doc.on.doc"
		}
	}
}

private enum MotionVariant: String, CaseIterable, Identifiable {
	case topDown
	case reveal
	case softSpring
	case fade
	case scale
	case blur

	var id: Self { self }

	var title: String {
		switch self {
		case .topDown: "Сверху вниз"
		case .reveal: "Раскрытие"
		case .softSpring: "Мягкая пружина"
		case .fade: "Только прозрачность"
		case .scale: "Масштаб"
		case .blur: "Фокус"
		}
	}

	var note: String {
		switch self {
		case .topDown: "Понятное направление, мало шума"
		case .reveal: "Строка разворачивается от верхней границы"
		case .softSpring: "Чуть живее, но заметнее при частых действиях"
		case .fade: "Спокойно, положение новой строки считывается хуже"
		case .scale: "Подходит карточкам, слабее ощущается как список"
		case .blur: "Выразительно, может отвлекать от текста"
		}
	}

	var isRecommended: Bool { self == .topDown }

	func animation(duration: Double, reduceMotion: Bool) -> Animation {
		if reduceMotion { return .easeOut(duration: 0.08) }
		switch self {
		case .topDown, .reveal, .fade, .scale, .blur:
			return .easeInOut(duration: duration)
		case .softSpring:
			return .spring(duration: duration, bounce: 0.22)
		}
	}

	func transition(reduceMotion: Bool) -> AnyTransition {
		if reduceMotion { return .opacity }
		switch self {
		case .topDown:
			return .asymmetric(
				insertion: .modifier(
					active: ContainedTopSlideModifier(progress: 0),
					identity: ContainedTopSlideModifier(progress: 1)
				),
				removal: .modifier(
					active: ContainedTopSlideModifier(progress: 0),
					identity: ContainedTopSlideModifier(progress: 1)
				)
			)
		case .reveal:
			return .asymmetric(
				insertion: .modifier(
					active: RevealModifier(progress: 0),
					identity: RevealModifier(progress: 1)
				),
				removal: .modifier(
					active: RevealModifier(progress: 0),
					identity: RevealModifier(progress: 1)
				)
			)
		case .softSpring:
			return .asymmetric(
				insertion: .offset(y: -18).combined(with: .opacity),
				removal: .offset(x: 22).combined(with: .opacity)
			)
		case .fade:
			return .opacity
		case .scale:
			return .asymmetric(
				insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
				removal: .scale(scale: 0.97, anchor: .top).combined(with: .opacity)
			)
		case .blur:
			return .asymmetric(
				insertion: .modifier(
					active: FocusModifier(opacity: 0, blur: 8, offset: -8),
					identity: FocusModifier(opacity: 1, blur: 0, offset: 0)
				),
				removal: .modifier(
					active: FocusModifier(opacity: 0, blur: 5, offset: 6),
					identity: FocusModifier(opacity: 1, blur: 0, offset: 0)
				)
			)
		}
	}
}

nonisolated private struct ContainedTopSlideModifier: ViewModifier, Animatable {
	var progress: CGFloat

	var animatableData: CGFloat {
		get { progress }
		set { progress = newValue }
	}

	func body(content: Content) -> some View {
		content
			.offset(y: -8 * (1 - progress))
			.mask(alignment: .top) {
				Rectangle()
					.scaleEffect(
						x: 1,
						y: max(progress, 0.001),
						anchor: .top
					)
			}
			.clipped()
	}
}

nonisolated private struct RevealModifier: ViewModifier, Animatable {
	var progress: CGFloat

	var animatableData: CGFloat {
		get { progress }
		set { progress = newValue }
	}

	func body(content: Content) -> some View {
		content
			.scaleEffect(x: 1, y: max(progress, 0.001), anchor: .top)
			.opacity(progress)
			.clipped()
	}
}

nonisolated private struct FocusModifier: ViewModifier, Animatable {
	var opacity: CGFloat
	var blur: CGFloat
	var offset: CGFloat

	var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
		get { AnimatablePair(opacity, AnimatablePair(blur, offset)) }
		set {
			opacity = newValue.first
			blur = newValue.second.first
			offset = newValue.second.second
		}
	}

	func body(content: Content) -> some View {
		content
			.opacity(opacity)
			.blur(radius: blur)
			.offset(y: offset)
	}
}

private struct LabItem: Identifiable, Hashable {
	let id: Int
	let title: String
	let preview: String
	let time: String
	let kind: ItemKind
}

private struct ListAnimationLab: View {
	@State private var kind = ItemKind.entry
	@State private var duration = 0.26
	@State private var reduceMotion = false
	@State private var nextID = 100
	@State private var itemsByVariant: [MotionVariant: [LabItem]] = [:]
	@State private var selectionByVariant: [MotionVariant: Int] = [:]

	private let columns = [
		GridItem(.adaptive(minimum: 360, maximum: 520), spacing: 16)
	]

	var body: some View {
		VStack(spacing: 0) {
			header
			Divider()
			ScrollView {
				LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
					ForEach(MotionVariant.allCases) { variant in
						VariantCard(
							variant: variant,
							items: itemsByVariant[variant] ?? [],
							selection: binding(for: variant),
							reduceMotion: reduceMotion,
							add: { add(to: variant) },
							remove: { remove(from: variant) }
						)
					}
				}
				.padding(20)
			}
		}
		.background(Color(nsColor: .windowBackgroundColor))
		.onAppear { reset() }
		.onChange(of: kind) { reset() }
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack(alignment: .firstTextBaseline) {
				VStack(alignment: .leading, spacing: 4) {
					Text("Анимации добавления и удаления")
						.font(.title2.weight(.semibold))
					Text("Одинаковое действие запускается во всех вариантах")
						.font(.callout)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Button("Сбросить", systemImage: "arrow.counterclockwise", action: reset)
			}

			HStack(spacing: 16) {
				Picker("Список", selection: $kind) {
					ForEach(ItemKind.allCases) { kind in
						Label(kind.title, systemImage: kind.systemImage).tag(kind)
					}
				}
				.frame(width: 190)

				Button("Добавить во все", systemImage: "plus", action: addToAll)
					.buttonStyle(.borderedProminent)
				Button("Удалить верхние", systemImage: "trash", action: removeFromAll)

				Divider().frame(height: 22)

				Text("\(Int(duration * 1_000)) мс")
					.monospacedDigit()
					.frame(width: 60, alignment: .trailing)
				Slider(value: $duration, in: 0.12...0.6, step: 0.02)
					.frame(width: 150)
				Toggle("Уменьшение движения", isOn: $reduceMotion)
					.toggleStyle(.switch)
			}
		}
		.padding(20)
	}

	private func binding(for variant: MotionVariant) -> Binding<Int?> {
		Binding(
			get: { selectionByVariant[variant] },
			set: { selectionByVariant[variant] = $0 }
		)
	}

	private func addToAll() {
		let item = makeItem()
		for variant in MotionVariant.allCases {
			withAnimation(variant.animation(duration: duration, reduceMotion: reduceMotion)) {
				itemsByVariant[variant, default: []].insert(item, at: 0)
				selectionByVariant[variant] = item.id
			}
		}
	}

	private func removeFromAll() {
		for variant in MotionVariant.allCases {
			guard let first = itemsByVariant[variant]?.first else { continue }
			withAnimation(variant.animation(duration: duration, reduceMotion: reduceMotion)) {
				itemsByVariant[variant]?.removeAll { $0.id == first.id }
				if selectionByVariant[variant] == first.id {
					selectionByVariant[variant] = nil
				}
			}
		}
	}

	private func add(to variant: MotionVariant) {
		let item = makeItem()
		withAnimation(variant.animation(duration: duration, reduceMotion: reduceMotion)) {
			itemsByVariant[variant, default: []].insert(item, at: 0)
			selectionByVariant[variant] = item.id
		}
	}

	private func remove(from variant: MotionVariant) {
		guard let items = itemsByVariant[variant], !items.isEmpty else { return }
		let selectedID = selectionByVariant[variant]
		let removedID = selectedID.flatMap { id in items.first { $0.id == id }?.id } ?? items[0].id
		withAnimation(variant.animation(duration: duration, reduceMotion: reduceMotion)) {
			itemsByVariant[variant]?.removeAll { $0.id == removedID }
			selectionByVariant[variant] = nil
		}
	}

	private func reset() {
		var lists: [MotionVariant: [LabItem]] = [:]
		let initial = sampleItems(kind: kind)
		for variant in MotionVariant.allCases {
			lists[variant] = initial
		}
		itemsByVariant = lists
		selectionByVariant = [:]
	}

	private func makeItem() -> LabItem {
		defer { nextID += 1 }
		let number = nextID - 99
		let title: String
		let preview: String
		switch kind {
		case .entry:
			title = "Новая запись \(number)"
			preview = "Строка добавлена в начало списка. Остальные записи сдвигаются вниз."
		case .bookmark:
			title = "Важная мысль \(number)"
			preview = "Закладка остаётся заметной, но анимация не спорит с иконкой."
		case .archive:
			title = "Архивная запись \(number)"
			preview = "Перемещение в архив меняет состав двух списков."
		case .trash:
			title = "Удалённая запись \(number)"
			preview = "В корзине строка появляется после удаления из основного списка."
		case .template:
			title = "Темплейт \(number)"
			preview = "Заголовок\nКонтекст\nСледующий шаг"
		}
		return LabItem(id: nextID, title: title, preview: preview, time: "сейчас", kind: kind)
	}
}

private struct VariantCard: View {
	let variant: MotionVariant
	let items: [LabItem]
	@Binding var selection: Int?
	let reduceMotion: Bool
	let add: () -> Void
	let remove: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			cardHeader
			Divider()
			ScrollView {
				LazyVStack(spacing: 0) {
					ForEach(items) { item in
						VStack(spacing: 0) {
							ItemRow(item: item, isSelected: selection == item.id)
							Divider().padding(.leading, 12)
						}
						.background(Color(nsColor: .textBackgroundColor))
						.contentShape(.rect)
						.clipped()
						.onTapGesture { selection = item.id }
						.transition(variant.transition(reduceMotion: reduceMotion))
					}
				}
			}
			.frame(height: 250)
			.background(.background)
		}
		.background(.background)
		.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.stroke(
					variant.isRecommended ? Color.accentColor.opacity(0.75) : Color(nsColor: .separatorColor),
					lineWidth: variant.isRecommended ? 2 : 1)
		}
		.shadow(color: .black.opacity(0.06), radius: 8, y: 3)
	}

	private var cardHeader: some View {
		VStack(alignment: .leading, spacing: 9) {
			HStack {
				Text(variant.title)
					.font(.headline)
				if variant.isRecommended {
					Text("Кандидат")
						.font(.caption.weight(.semibold))
						.foregroundStyle(Color.accentColor)
						.padding(.horizontal, 7)
						.padding(.vertical, 2)
						.background(Color.accentColor.opacity(0.12), in: Capsule())
				}
				Spacer()
				Button(action: add) { Image(systemName: "plus") }
					.buttonStyle(.borderless)
					.help("Добавить строку")
				Button(action: remove) { Image(systemName: "trash") }
					.buttonStyle(.borderless)
					.disabled(items.isEmpty)
					.help(selection == nil ? "Удалить верхнюю строку" : "Удалить выбранную строку")
			}
			Text(variant.note)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
		.padding(14)
	}
}

private struct ItemRow: View {
	let item: LabItem
	let isSelected: Bool

	var body: some View {
		HStack(alignment: .top, spacing: 10) {
			Image(systemName: item.kind.systemImage)
				.font(.system(size: 13, weight: .medium))
				.foregroundStyle(iconColor)
				.frame(width: 18, height: 20)

			VStack(alignment: .leading, spacing: 4) {
				HStack {
					Text(item.title)
						.font(.headline)
						.lineLimit(1)
					Spacer(minLength: 8)
					Text(item.time)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Text(item.preview.replacingOccurrences(of: "\n", with: " · "))
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(2)
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
	}

	private var iconColor: Color {
		switch item.kind {
		case .bookmark: .orange
		case .trash: .red.opacity(0.8)
		case .archive: .secondary
		case .entry, .template: .accentColor
		}
	}
}

private func sampleItems(kind: ItemKind) -> [LabItem] {
	let values: [(String, String, String)] =
		switch kind {
		case .entry:
			[
				("Решения после продуктовой встречи", "Сделать движение коротким и сохранить позицию чтения.", "10:42"),
				("Утренние заметки", "Дождь закончился до завтрака. Записал две идеи по дороге.", "08:15"),
				("Поездка в Казбеги", "Проверить погоду у перевала и выехать до пробок.", "вчера"),
			]
		case .bookmark:
			[
				(
					"Движение должно объяснять изменение",
					"Если анимацию замечают раньше содержания, она слишком сильная.", "сегодня"
				),
				("Книги, к которым стоит вернуться", "Ways of Seeing и старая книга по типографике.", "вчера"),
				("Маршрут по Сванетии", "Сохранённый план на сентябрь.", "12 окт."),
			]
		case .archive:
			[
				("Итоги сентября", "Закрытые задачи и решения за месяц.", "1 окт."),
				("Черновик старого онбординга", "Оставлен для истории продукта.", "18 сент."),
				("Планы на лето", "Маршруты и список вещей.", "2 июня"),
			]
		case .trash:
			[
				("Дубликат заметки", "Будет удалён навсегда через 30 дней.", "сегодня"),
				("Список покупок", "Хлеб, молоко, кофе.", "вчера"),
				("Пустой черновик", "Без дополнительного текста.", "24 окт."),
			]
		case .template:
			[
				("Еженедельный обзор", "Что получилось · Что мешало · Следующая неделя", "20 окт."),
				("Решение", "Контекст · Варианты · Выбор · Последствия", "12 окт."),
				("Встреча", "Участники · Заметки · Следующие шаги", "3 окт."),
			]
		}

	return values.enumerated().map { index, value in
		LabItem(
			id: index + 1,
			title: value.0,
			preview: value.1,
			time: value.2,
			kind: kind
		)
	}
}
