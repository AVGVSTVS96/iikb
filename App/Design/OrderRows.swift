import SwiftUI

/// Rows put in order by dragging the handle at their left, for a `Box`, which draws the hairlines between them; each
/// row is as tall as the page's others and its switch sits where theirs do. VoiceOver moves a row with Move Up and Move
/// Down. The order is saved once, when the row is let go, and a drag the system takes away (a scroll, a call) puts the
/// rows back as they were.
struct OrderRows<Item: Hashable, Label: View>: View {
    @Binding var items: [Item]
    /// Whether an item takes part in the order: those that do come first, and one that doesn't has an empty slot in the
    /// handle's place, so every row's title lines up.
    var moves: (Item) -> Bool = { _ in true }
    @ViewBuilder var label: (Item) -> Label

    @State private var dragging: [Item]?
    @State private var lifted: Item?
    @State private var start = 0
    @State private var lift: CGFloat = 0
    @State private var pitch: CGFloat = 57
    @GestureState private var held = false

    private var shown: [Item] { dragging ?? items }
    private var movable: Int { shown.prefix { moves($0) }.count }

    var body: some View {
        ForEach(shown, id: \.self) { item in
            let index = shown.firstIndex(of: item) ?? 0
            HStack(spacing: 12) {
                if moves(item) { handle(item) } else { Color.clear.frame(width: 22, height: 22) }
                label(item)
                    .accessibilityActions {
                        if moves(item), index > 0 { Button("Move Up") { move(item, to: index - 1) } }
                        if moves(item), index < movable - 1 { Button("Move Down") { move(item, to: index + 1) } }
                    }
            }
            .row()
            .background(Color.appCard)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                pitch = $0 + 1
            }
            .offset(y: lifted == item ? lift : 0)
            .shadow(color: .black.opacity(lifted == item ? 0.18 : 0), radius: 10, y: 3)
            .zIndex(lifted == item ? 1 : 0)
            .sensoryFeedback(.selection, trigger: lifted == item ? dragging : nil)
            .onChange(of: held) { _, isHeld in
                if !isHeld, lifted == item { settle(saving: false) }
            }
        }
    }

    private func handle(_ item: Item) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.body.weight(.medium))
            .foregroundStyle(Color.appSecondary)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle().inset(by: -12))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($held) { _, held, _ in held = true }
                    .onChanged { drag in
                        if lifted == nil {
                            dragging = items
                            lifted = item
                            start = items.firstIndex(of: item) ?? 0
                        }
                        guard var order = dragging, let at = order.firstIndex(of: item) else { return }
                        let to = min(max(start + Int((drag.translation.height / pitch).rounded()), 0), movable - 1)
                        if to != at {
                            order.move(fromOffsets: [at], toOffset: to > at ? to + 1 : to)
                            withAnimation(.snappy(duration: 0.2)) { dragging = order }
                        }
                        lift = drag.translation.height - CGFloat(to - start) * pitch
                    }
                    .onEnded { _ in settle(saving: true) }
            )
            .accessibilityHidden(true)
    }

    /// Lets the lifted row down: in its new place when the drag ended, back where it was when the drag was taken away.
    private func settle(saving: Bool) {
        if saving, let dragging, dragging != items { items = dragging }
        if !saving { withAnimation(.snappy(duration: 0.25)) { dragging = items } }
        withAnimation(.snappy(duration: 0.25)) {
            lift = 0
            lifted = nil
        } completion: {
            dragging = nil
        }
    }

    private func move(_ item: Item, to index: Int) {
        guard let at = items.firstIndex(of: item) else { return }
        withAnimation(.snappy) { items.move(fromOffsets: [at], toOffset: index > at ? index + 1 : index) }
    }
}
