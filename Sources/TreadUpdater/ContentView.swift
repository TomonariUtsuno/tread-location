import AppKit
import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: DraftStore
    @State private var showingFileImporter = false
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                editorHeader
                DropZone(isTargeted: $isDropTargeted) {
                    showingFileImporter = true
                }
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: receiveDrop)

                Divider()

                if store.drafts.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("追加する画像を読み込んでください")
                            .font(.headline)
                        Text("ここで入力する内容は公開前の未確定ドラフトです。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(store.drafts) { draft in
                                DraftEditorRow(draft: draft, onChange: store.revalidate, onRemove: { store.remove(draft) })
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 470, max: 560)
        } detail: {
            MapPreview()
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                store.addFiles(urls)
            }
        }
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("tread 更新")
                .font(.system(size: 24, weight: .regular, design: .rounded))
            Text("公開前の未確定ドラフト。GitHubや公開サイトは変更しません。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    store.addFiles([url])
                }
            }
        }
        return !providers.isEmpty
    }
}

private struct DropZone: View {
    @Binding var isTargeted: Bool
    let chooseFiles: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "arrow.down.doc")
                .font(.title2)
                .foregroundStyle(isTargeted ? .white : Color.accentColor)
            Text("画像をここへドロップ")
                .font(.headline)
            Text("PNG・横533 × 縦800 px／複数枚を一度に追加できます")
                .font(.caption)
                .multilineTextAlignment(.center)
            Text("ファイル名は w056.png の形式（w＋3桁の車輪番号）にしてください")
                .font(.caption)
                .multilineTextAlignment(.center)
            Button("画像を選択…", action: chooseFiles)
                .buttonStyle(.bordered)
                .padding(.top, 3)
        }
        .foregroundStyle(isTargeted ? .white : .primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(isTargeted ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5]))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .accessibilityLabel("複数画像の追加")
    }
}

private struct DraftEditorRow: View {
    @ObservedObject var draft: DraftWheel
    let onChange: () -> Void
    let onRemove: () -> Void

    private var numberBinding: Binding<String> {
        Binding(
            get: { draft.numberText },
            set: { draft.numberText = $0; onChange() }
        )
    }

    private var coordinateBinding: Binding<String> {
        Binding(
            get: { draft.coordinateText },
            set: { draft.coordinateText = $0; onChange() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let image = draft.inspection?.preview {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 120)
                        .background(.black)
                        .accessibilityLabel("読み込んだ車輪画像")
                } else {
                    Image(systemName: "photo.badge.exclamationmark")
                        .frame(width: 80, height: 120)
                        .background(Color.secondary.opacity(0.12))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(draft.sourceFilename)
                        .font(.headline)
                        .textSelection(.enabled)
                    if let inspection = draft.inspection {
                        Text(inspection.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("画像情報を取得できませんでした")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let outputFilename = draft.outputFilename {
                        Text("公開予定名: \(outputFilename)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("\(draft.sourceFilename) を一覧から外す")
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("車輪番号")
                    .frame(width: 74, alignment: .leading)
                TextField("例: 56", text: numberBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 130)
                    .accessibilityLabel("車輪番号")
                if draft.suggestedNumber != nil {
                    Text("ファイル名から推定")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("取得座標")
                TextField("N34°31'22.98\" E135°36'27.93\"", text: coordinateBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("取得座標。度分秒または緯度、経度を一つの欄へ入力")
                if let coordinates = draft.parsedCoordinates {
                    Text("lat: \(coordinates.latitudeText)   lng: \(coordinates.longitudeText)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if !draft.issues.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(draft.issues) { issue in
                        IssueLabel(issue: issue)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(draft.hasBlockingError ? Color.red.opacity(0.55) : Color.secondary.opacity(0.22))
        }
        .accessibilityElement(children: .contain)
    }
}

private struct IssueLabel: View {
    let issue: DraftIssue

    var body: some View {
        Label(issue.message, systemImage: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(issue.severity == .error ? .red : .orange)
    }
}

private struct MapPreview: View {
    @EnvironmentObject private var store: DraftStore
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3, longitude: 138.1),
        span: MKCoordinateSpan(latitudeDelta: 9.5, longitudeDelta: 9.5)
    )

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("地点プレビュー")
                        .font(.headline)
                    Text("灰色は既存地点、橙色は今回の追加予定地点です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("追加予定地点を表示", action: fitDrafts)
                    .disabled(store.validDrafts.isEmpty)
            }
            .padding(16)

            Map(coordinateRegion: $region, annotationItems: store.previewPoints) { point in
                MapAnnotation(coordinate: point.coordinate) {
                    Button {
                        if case let .draft(id) = point.kind { store.select(id) }
                    } label: {
                        Text("\(point.number)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(pinColor(point.kind))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pinLabel(point))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            selectedSummary
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.bar)
        }
    }

    @ViewBuilder
    private var selectedSummary: some View {
        if let draft = store.selectedDraft(), let coordinates = draft.parsedCoordinates {
            HStack(spacing: 12) {
                if let image = draft.inspection?.preview {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 62)
                        .background(.black)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("追加予定 No.\(draft.numberText)")
                        .font(.headline)
                    Text("lat: \(coordinates.latitudeText)   lng: \(coordinates.longitudeText)")
                        .font(.system(.caption, design: .monospaced))
                }
            }
        } else {
            Text("有効な座標を入力すると、追加予定地点が橙色で表示されます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func fitDrafts() {
        let points = store.previewPoints.compactMap { point -> CLLocationCoordinate2D? in
            if case .draft = point.kind { return point.coordinate }
            return nil
        }
        guard let first = points.first else { return }
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let latitudeDelta = max((latitudes.max() ?? first.latitude) - (latitudes.min() ?? first.latitude), 0.02) * 1.6
        let longitudeDelta = max((longitudes.max() ?? first.longitude) - (longitudes.min() ?? first.longitude), 0.02) * 1.6
        region = MKCoordinateRegion(
            center: .init(latitude: latitudes.reduce(0, +) / Double(latitudes.count), longitude: longitudes.reduce(0, +) / Double(longitudes.count)),
            span: .init(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    private func pinColor(_ kind: PreviewPoint.Kind) -> Color {
        if case .draft = kind { return .orange }
        return Color(white: 0.2)
    }

    private func isDraft(_ kind: PreviewPoint.Kind) -> Bool {
        if case .draft = kind { return true }
        return false
    }

    private func pinLabel(_ point: PreviewPoint) -> String {
        "\(isDraft(point.kind) ? "追加予定" : "既存")の車輪 No.\(point.number)"
    }
}
