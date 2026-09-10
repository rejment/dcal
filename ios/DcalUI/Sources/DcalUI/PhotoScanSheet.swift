// Going through what the scan found, one day at a time.
//
// Nothing is added on its own. A day with forty photos was a wedding or a
// flooded kitchen, and only you know which - so tapping a row opens the
// ordinary event editor with the dates, length and category already filled
// in, and you supply the one thing the phone cannot.

import DcalKit
import SwiftUI

struct PhotoScanSheet: View {
    let model: TimelineModel
    let onClose: () -> Void

    @State private var access = PhotoLibrary.access
    @State private var findings: [PhotoFinding] = []
    @State private var names: [String: String] = [:]
    @State private var added: Set<String> = []
    @State private var working = false
    @State private var hasScanned = false
    @State private var editing: PhotoFinding?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("From your photos")
                .compactNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onClose)
                    }
                }
        }
        .sheet(item: $editing) { finding in
            EventEditSheet(
                event: finding.proposedEvent(title: names[finding.id] ?? ""),
                isNew: true,
                onSave: { event in
                    model.save(event)
                    added.insert(finding.id)
                    editing = nil
                },
                onDelete: nil,
                onCancel: { editing = nil }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch access {
        case .denied:
            message(
                "DCAL can't see your photos",
                "Turn it on under Settings → Privacy & Security → Photos → DCAL. "
                    + "Only the date and place of each photo is read, never the picture."
            )
        case .notAsked:
            invitation
        case .allowed, .limited:
            if working {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Looking through the dates…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasScanned {
                invitation
            } else if findings.isEmpty {
                message(
                    "Nothing stood out",
                    "Either the photos have no dates on them, or no stretch looked "
                        + "different enough from the rest to be worth pulling out."
                )
            } else {
                list
            }
        }
    }

    private var invitation: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your photos already know when things happened.")
                .font(Theme.display(23, weight: .regular))
                .foregroundStyle(Theme.chalk)

            Text("""
            This looks at the date and place of each photo — never the picture \
            itself, and nothing leaves the phone. It picks out the days that \
            look different from your ordinary ones: time spent away from home, \
            days you took far more photos than usual, days holding photos you \
            hearted, and the first photos after months of quiet.

            You choose what to keep, and you name it.
            """)
            .font(.system(size: 15))
            .foregroundStyle(.secondary)

            Button("Look through my photos") {
                Task { await scan() }
            }
            .buttonStyle(RailButtonStyle(prominent: true))

            Spacer()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var list: some View {
        List {
            if access == .limited {
                Section {
                    Text("You've given DCAL only some of your photos, so this is what those show.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(findings) { finding in
                    Button { editing = finding } label: { row(finding) }
                        .buttonStyle(.plain)
                }
            } header: {
                Text("\(findings.count) days worth a look")
            } footer: {
                Text("Dates come from the photos themselves. Anything scanned in "
                    + "later — an old print, a screenshot — carries the date it was "
                    + "scanned, not the day it happened.")
            }
        }
    }

    private func row(_ finding: PhotoFinding) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(names[finding.id] ?? span(finding))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.chalk)

                if names[finding.id] != nil {
                    Text(span(finding))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Text(scale(finding))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                HStack(spacing: 5) {
                    ForEach(finding.reasons, id: \.self) { reason in
                        Text(reason.label)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.panelRaised, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 8)
            Image(systemName: added.contains(finding.id) ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 20))
                .foregroundStyle(added.contains(finding.id) ? Theme.amber : Theme.fog)
        }
        .padding(.vertical, 4)
    }

    private func span(_ finding: PhotoFinding) -> String {
        if finding.dayCount <= 1 {
            return finding.start.formatted(date: .long, time: .omitted)
        }
        return finding.start.formatted(date: .abbreviated, time: .omitted)
            + " – " + finding.lastDay.formatted(date: .abbreviated, time: .omitted)
    }

    private func scale(_ finding: PhotoFinding) -> String {
        let photos = "\(finding.photoCount) photo\(finding.photoCount == 1 ? "" : "s")"
        return finding.dayCount > 1 ? "\(photos) over \(finding.dayCount) days" : photos
    }

    private func message(_ title: String, _ body: String) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(Theme.display(21, weight: .regular))
                .foregroundStyle(Theme.chalk)
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scan() async {
        if access == .notAsked { access = await PhotoLibrary.request() }
        guard access == .allowed || access == .limited else { return }

        working = true
        let moments = await PhotoLibrary.moments()
        let found = PhotoScan.findings(in: moments, calendar: model.calendar)
        findings = found
        hasScanned = true
        working = false

        // Names arrive after the list does; a trip with no name is still worth
        // showing, and geocoding is slow enough to wait behind.
        names = await PhotoLibrary.placeNames(for: found)
    }
}
