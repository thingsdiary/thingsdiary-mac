#if DEBUG
	import SwiftUI

	private enum TabOverlapStrategy: CaseIterable, Identifiable {
		case reservedLane
		case trailingMask
		case clampedDrag
		case hiddenCreateButton
		case conditionalCreateButton

		var id: Self { self }

		var title: String {
			switch self {
			case .reservedLane: "Reserved lane"
			case .trailingMask: "Trailing mask"
			case .clampedDrag: "Clamped drag"
			case .hiddenCreateButton: "Hide + while dragging"
			case .conditionalCreateButton: "Hide inline + only"
			}
		}

		var detail: String {
			switch self {
			case .reservedLane:
				"The tab viewport ends before the + button. Dragged tabs are clipped at that edge."
			case .trailingMask:
				"The strip keeps its current layout. A mask removes tab pixels under the + button."
			case .clampedDrag:
				"The dragged tab stops at the leading edge of the + button."
			case .hiddenCreateButton:
				"The + button leaves the hierarchy until the drop finishes."
			case .conditionalCreateButton:
				"An inline + hides during dragging. A pinned + stays visible while tabs are clipped at its boundary."
			}
		}
	}

	private enum TabOverlapScenario: CaseIterable, Identifiable {
		case inline
		case pinned

		var id: Self { self }

		var title: String {
			switch self {
			case .inline: "2 tabs, inline +"
			case .pinned: "Overflow, pinned +"
			}
		}

		var initialTabIDs: [String] {
			switch self {
			case .inline: ["one", "two"]
			case .pinned: ["one", "two", "three", "four", "five"]
			}
		}
	}

	struct TabOverlapLab: View {
		private let columns = [
			GridItem(.flexible(minimum: 460), spacing: 20),
			GridItem(.flexible(minimum: 460), spacing: 20),
		]

		var body: some View {
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					VStack(alignment: .leading, spacing: 6) {
						Text("Tab and + overlap")
							.font(.largeTitle.bold())
						Text("Drag the first tab to the right. Each option shows inline and pinned + placement.")
							.foregroundStyle(.secondary)
					}

					LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
						ForEach(TabOverlapStrategy.allCases) { strategy in
							TabOverlapExample(strategy: strategy)
						}
					}
				}
				.padding(24)
			}
			.frame(minWidth: 980, minHeight: 720)
			.background(Color(nsColor: .windowBackgroundColor))
		}
	}

	private struct TabOverlapExample: View {
		let strategy: TabOverlapStrategy

		var body: some View {
			VStack(alignment: .leading, spacing: 14) {
				Text(strategy.title)
					.font(.headline)

				Text(strategy.detail)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)

				ForEach(TabOverlapScenario.allCases) { scenario in
					VStack(alignment: .leading, spacing: 6) {
						Text(scenario.title)
							.font(.caption.weight(.medium))
							.foregroundStyle(.secondary)
						TabOverlapStrip(strategy: strategy, scenario: scenario)
					}
				}
			}
			.padding(16)
			.frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
			.background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
		}
	}

	private struct TabOverlapStrip: View {
		let strategy: TabOverlapStrategy
		let scenario: TabOverlapScenario

		@State private var tabIDs: [String]
		@State private var activeTabID: String
		@State private var reorderSession: TabReorderSession<String>?
		@State private var nextTabNumber = 6

		init(strategy: TabOverlapStrategy, scenario: TabOverlapScenario) {
			self.strategy = strategy
			self.scenario = scenario
			_tabIDs = State(initialValue: scenario.initialTabIDs)
			_activeTabID = State(initialValue: scenario.initialTabIDs.last ?? "")
		}

		private var buttonLaneWidth: CGFloat {
			browserTabCreateButtonWidth + browserTabCreateButtonSpacing
		}

		var body: some View {
			GeometryReader { proxy in
				let availableWidth = max(proxy.size.width, 0)
				let tabWidth = adaptiveBrowserTabWidth(
					availableWidth: availableWidth,
					tabCount: tabIDs.count
				)
				let tabsContentWidth = browserTabsContentWidth(
					tabWidth: tabWidth,
					tabCount: tabIDs.count
				)
				let buttonOffset = browserTabCreateButtonOffset(
					availableWidth: availableWidth,
					tabsContentWidth: tabsContentWidth
				)

				switch strategy {
				case .reservedLane:
					reservedLaneStrip(
						tabWidth: tabWidth,
						availableWidth: availableWidth,
						tabsContentWidth: tabsContentWidth
					)
				case .trailingMask:
					overlaidStrip(
						tabWidth: tabWidth,
						availableWidth: availableWidth,
						buttonOffset: buttonOffset,
						masksTabsAtButton: true,
						hidesButtonWhileDragging: false
					)
				case .clampedDrag:
					overlaidStrip(
						tabWidth: tabWidth,
						availableWidth: availableWidth,
						buttonOffset: buttonOffset,
						masksTabsAtButton: scenario == .pinned,
						hidesButtonWhileDragging: false
					)
				case .hiddenCreateButton:
					overlaidStrip(
						tabWidth: tabWidth,
						availableWidth: availableWidth,
						buttonOffset: buttonOffset,
						masksTabsAtButton: scenario == .pinned,
						hidesButtonWhileDragging: true
					)
				case .conditionalCreateButton:
					overlaidStrip(
						tabWidth: tabWidth,
						availableWidth: availableWidth,
						buttonOffset: buttonOffset,
						masksTabsAtButton: scenario == .pinned,
						hidesButtonWhileDragging: scenario == .inline
					)
				}
			}
			.frame(height: workspaceTitlebarHeight)
			.background(TitlebarMaterialBackground())
			.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 9, style: .continuous)
					.stroke(Color.primary.opacity(0.14))
			}
		}

		private func reservedLaneStrip(
			tabWidth: CGFloat,
			availableWidth: CGFloat,
			tabsContentWidth: CGFloat
		) -> some View {
			let viewportWidth = min(
				tabsContentWidth,
				max(availableWidth - buttonLaneWidth, 0)
			)

			return HStack(spacing: browserTabCreateButtonSpacing) {
				tabsScrollView(
					tabWidth: tabWidth,
					availableWidth: viewportWidth,
					addsTrailingButtonPadding: false
				)
				.frame(width: viewportWidth)
				.clipped()

				createTabButton
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}

		private func overlaidStrip(
			tabWidth: CGFloat,
			availableWidth: CGFloat,
			buttonOffset: CGFloat,
			masksTabsAtButton: Bool,
			hidesButtonWhileDragging: Bool
		) -> some View {
			ZStack(alignment: .leading) {
				tabsScrollView(tabWidth: tabWidth, availableWidth: availableWidth)
					.mask(alignment: .leading) {
						Rectangle()
							.frame(
								width: masksTabsAtButton ? max(buttonOffset, 0) : availableWidth
							)
					}

				if !hidesButtonWhileDragging || reorderSession == nil {
					createTabButton
						.offset(x: buttonOffset)
						.zIndex(4)
				}
			}
		}

		private func tabsScrollView(
			tabWidth: CGFloat,
			availableWidth: CGFloat,
			addsTrailingButtonPadding: Bool = true
		) -> some View {
			ScrollView(.horizontal, showsIndicators: false) {
				ZStack(alignment: .leading) {
					if let reorderSession {
						tabPlaceholder(width: tabWidth)
							.offset(
								x: CGFloat(reorderSession.placeholderIndex)
									* (tabWidth + browserTabSpacing)
							)
					}

					HStack(spacing: browserTabSpacing) {
						ForEach(Array(tabIDs.enumerated()), id: \.element) { index, tabID in
							BrowserTab(
								accessibilityIdentifier: "lab-tab-\(strategy.id)-\(scenario.id)-\(tabID)",
								closeAccessibilityIdentifier: "lab-tab.close-\(strategy.id)-\(scenario.id)-\(tabID)",
								title: title(for: tabID),
								width: tabWidth,
								isActive: activeTabID == tabID,
								isDirty: tabID == "two",
								isPinned: false,
								isPreview: false,
								isDragged: reorderSession?.tabID == tabID,
								horizontalOffset: reorderSession?.offset(
									forTabAt: index,
									tabWidth: tabWidth
								) ?? 0,
								activate: { activeTabID = tabID },
								close: { close(tabID) },
								reorder: {
									updateReorder(
										tabID,
										translation: $0,
										tabWidth: tabWidth,
										availableWidth: availableWidth
									)
								},
								finishReordering: { finishReorder(tabID) }
							)
						}
					}
				}
				.padding(.leading, browserTabLeadingPadding)
				.padding(.trailing, addsTrailingButtonPadding ? buttonLaneWidth : 0)
			}
		}

		private func tabPlaceholder(width: CGFloat) -> some View {
			RoundedRectangle(cornerRadius: 7, style: .continuous)
				.fill(Color.primary.opacity(0.035))
				.overlay {
					RoundedRectangle(cornerRadius: 7, style: .continuous)
						.stroke(
							Color.secondary.opacity(0.32),
							style: StrokeStyle(lineWidth: 1, dash: [4, 3])
						)
				}
				.frame(width: width, height: 30)
				.allowsHitTesting(false)
		}

		private var createTabButton: some View {
			IconButton(
				icon: .plus,
				usesTitlebarBackground: true,
				action: addTab
			)
			.frame(width: browserTabCreateButtonWidth)
			.accessibilityLabel("New Entry Tab")
			.help("New Entry Tab")
		}

		private func title(for tabID: String) -> String {
			switch tabID {
			case "one": "Project notes"
			case "two": "Draft"
			case "three": "Ideas"
			case "four": "Meeting"
			case "five": "Research"
			default: "Note \(tabID)"
			}
		}

		private func updateReorder(
			_ tabID: String,
			translation: CGFloat,
			tabWidth: CGFloat,
			availableWidth: CGFloat
		) {
			if reorderSession == nil,
				let startIndex = tabIDs.firstIndex(of: tabID)
			{
				reorderSession = TabReorderSession<String>(tabID: tabID, startIndex: startIndex)
				activeTabID = tabID
			}
			guard var session = reorderSession, session.tabID == tabID else { return }

			let translation =
				strategy == .clampedDrag
				? clampedTranslation(
					translation,
					session: session,
					tabWidth: tabWidth,
					availableWidth: availableWidth
				)
				: translation
			session.update(
				translation: translation,
				tabWidth: tabWidth,
				tabCount: tabIDs.count
			)
			reorderSession = session
		}

		private func clampedTranslation(
			_ translation: CGFloat,
			session: TabReorderSession<String>,
			tabWidth: CGFloat,
			availableWidth: CGFloat
		) -> CGFloat {
			guard translation > 0 else { return translation }
			let step = tabWidth + browserTabSpacing
			let tabTrailingEdge =
				browserTabLeadingPadding
				+ CGFloat(session.startIndex) * step
				+ tabWidth
			let tabsContentWidth = browserTabsContentWidth(
				tabWidth: tabWidth,
				tabCount: tabIDs.count
			)
			let buttonOffset = browserTabCreateButtonOffset(
				availableWidth: availableWidth,
				tabsContentWidth: tabsContentWidth
			)
			return min(translation, max(buttonOffset - browserTabSpacing - tabTrailingEdge, 0))
		}

		private func finishReorder(_ tabID: String) {
			guard let session = reorderSession, session.tabID == tabID else { return }
			withAnimation(.smooth(duration: 0.16)) {
				let movedID = tabIDs.remove(at: session.startIndex)
				let destination = min(max(session.placeholderIndex, 0), tabIDs.count)
				tabIDs.insert(movedID, at: destination)
				reorderSession = nil
			}
		}

		private func close(_ tabID: String) {
			guard let index = tabIDs.firstIndex(of: tabID) else { return }
			tabIDs.remove(at: index)
			if activeTabID == tabID {
				activeTabID = tabIDs.indices.contains(index) ? tabIDs[index] : tabIDs.last ?? ""
			}
		}

		private func addTab() {
			let tabID = String(nextTabNumber)
			nextTabNumber += 1
			tabIDs.append(tabID)
			activeTabID = tabID
		}
	}
#endif
