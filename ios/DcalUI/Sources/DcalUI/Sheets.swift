// Reading one thing, changing one thing, and the handful of actions that do
// not belong on the main screen.

import DcalKit
import SwiftUI
import UniformTypeIdentifiers

private let durationChoices: [(TimeInterval, String)] = [
    (0, "A moment"),
    (15 * 60, "15 minutes"),
    (30 * 60, "30 minutes"),
    (3600, "1 hour"),
    (2 * 3600, "2 hours"),
    (4 * 3600, "4 hours"),
    (86400, "All day"),
    (2 * 86400, "2 days"),
    (7 * 86400, "A week"),
    (14 * 86400, "2 weeks"),
    (30 * 86400, "A month"),
]

private func nearestChoice(to duration: TimeInterval) -> TimeInterval {
    durationChoices.min { abs($0.0 - duration) < abs($1.0 - duration) }?.0 ?? 0
}

private func whenText(_ event: Event, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.hour, .minute], from: event.start)
    if event.isMoment {
        let midnight = (parts.hour ?? 0) == 0 && (parts.minute ?? 0) == 0
        let date = event.start.formatted(date: .complete, time: .omitted)
        return midnight ? date : date + ", " + event.start.formatted(date: .omitted, time: .shortened)
    }
    if event.duration < 86400 {
        return event.start.formatted(date: .complete, time: .omitted)
            + ", " + event.start.formatted(date: .omitted, time: .shortened)
            + "–" + event.end.formatted(date: .omitted, time: .shortened)
    }
    let last = event.end.addingTimeInterval(-1)
    return event.start.formatted(date: .abbreviated, time: .omitted)
        + " to " + last.formatted(date: .abbreviated, time: .omitted)
}

struct EventDetailSheet: View {
    let event: Event
    let age: Int?
    let calendar: Calendar
    let onEdit: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(rgb: event.category.rgb))
                        .frame(width: 9, height: 9)
                    Text(event.category.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.fog)
                }
                .padding(.bottom, 10)

                Text(event.title)
                    .font(Theme.display(24, weight: .regular))
                    .foregroundStyle(Theme.chalk)
                    .padding(.bottom, 4)

                Text(whenText(event, calendar: calendar))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.fog)

                if let sentence = ageSentence {
                    Text(sentence)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.amber.opacity(0.85))
                        .padding(.top, 3)
                }

                if !event.note.isEmpty {
                    Text(event.note)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(Color(hex: 0xC6D0E4))
                        .textSelection(.enabled)
                        .padding(.top, 16)
                }

                HStack(spacing: 9) {
                    Button("Edit", action: onEdit)
                        .buttonStyle(RailButtonStyle(prominent: true))
                        .frame(maxWidth: .infinity)
                    Button("Close", action: onClose)
                        .buttonStyle(RailButtonStyle())
                }
                .padding(.top, 22)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Theme.panel)
    }

    private var ageSentence: String? {
        guard let age, age > 0 else { return nil }
        return event.start < Date() ? "You were \(age)." : "You'll be \(age)."
    }
}

struct EventEditSheet: View {
    @State var draft: Event
    let isNew: Bool
    let onSave: (Event) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var chosenDuration: TimeInterval

    init(
        event: Event,
        isNew: Bool,
        onSave: @escaping (Event) -> Void,
        onDelete: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: event)
        _chosenDuration = State(initialValue: nearestChoice(to: event.duration))
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Dentist, Japan, started school…", text: $draft.title)
                        .font(.system(size: 17))
                } header: {
                    Text("What is it?")
                }

                Section {
                    DatePicker("Starts", selection: $draft.start)
                    Picker("How long", selection: $chosenDuration) {
                        ForEach(durationChoices, id: \.0) { choice in
                            Text(choice.1).tag(choice.0)
                        }
                    }
                }

                Section {
                    Picker("How big", selection: $draft.weight) {
                        ForEach(Weight.allCases, id: \.self) { weight in
                            Text(weight.label).tag(weight)
                        }
                    }
                    Picker("Part of life", selection: $draft.category) {
                        ForEach(Category.allCases, id: \.self) { category in
                            Text(category.label).tag(category)
                        }
                    }
                } footer: {
                    Text("How big decides how far you can zoom out and still see it.")
                }

                Section {
                    TextField("Optional", text: $draft.note, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Anything to remember")
                }

                if let onDelete {
                    Section {
                        Button("Delete this event", role: .destructive, action: onDelete)
                    }
                }
            }
            .navigationTitle(isNew ? "New event" : "Edit event")
            .compactNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = draft
                        saved.duration = chosenDuration
                        if saved.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            saved.title = "Untitled"
                        }
                        onSave(saved)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct MenuSheet: View {
    let model: TimelineModel
    let onClose: () -> Void

    @State private var jumpTo: Date
    @State private var exportURL: URL?
    @State private var picking = false
    /// Parsed and waiting for you to say what to do with it. Nothing is
    /// touched until you choose.
    @State private var incoming: Lifeline?
    @State private var problem: String?

    init(model: TimelineModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _jumpTo = State(initialValue: model.scale.centre)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $jumpTo, displayedComponents: .date)
                    Button("Go to this date") {
                        model.glide(to: jumpTo, pointsPerSecond: exp(model.logScale), duration: 0.6)
                        onClose()
                    }
                } header: {
                    Text("Jump")
                }

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Save a copy", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Label("Preparing…", systemImage: "square.and.arrow.up")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        picking = true
                    } label: {
                        Label("Open a file", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("""
                    A plain JSON file, one event per line, dates in your own \
                    time. Edit it on a computer and open it again here, or keep \
                    it somewhere safe as a backup.
                    """)
                }

                Section {
                    Button("Reset to the sample lifeline", role: .destructive) {
                        model.resetToSample()
                        onClose()
                    }
                } footer: {
                    Text("Replaces everything with the made-up life the app ships with.")
                }

                Section {
                    Text("""
                    Pinch to zoom, or use the scale buttons. Double-tap to zoom into a spot. \
                    Press and hold anywhere on the timeline to add something there.

                    Everything you add is stored on this phone only.
                    """)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Lifeline")
            .compactNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
        .task {
            exportURL = try? model.writeExport()
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json, .plainText]) { result in
            switch result {
            case .success(let url):
                do { incoming = try model.read(fileAt: url) }
                catch { problem = error.localizedDescription }
            case .failure(let error):
                problem = error.localizedDescription
            }
        }
        .confirmationDialog(
            incoming.map { "\($0.events.count) events in that file" } ?? "",
            isPresented: Binding(get: { incoming != nil }, set: { if !$0 { incoming = nil } }),
            titleVisibility: .visible
        ) {
            Button("Replace all \(model.lifeline.events.count)", role: .destructive) {
                if let incoming { model.replace(with: incoming) }
                incoming = nil
                onClose()
            }
            Button("Add to what's here") {
                if let incoming { model.add(incoming) }
                incoming = nil
                onClose()
            }
            Button("Cancel", role: .cancel) { incoming = nil }
        }
        .alert(
            "Couldn't read that file",
            isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
        ) {
            Button("OK") { problem = nil }
        } message: {
            Text(problem ?? "")
        }
    }
}
