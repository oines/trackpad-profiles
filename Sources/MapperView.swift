import AppKit
import SwiftUI

struct MapperView: View {
    @ObservedObject var store: MapperStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                if let profile = store.selectedProfile {
                    profileEditor(profile)
                        .id(profile.id)
                } else {
                    VStack(spacing: 10) {
                        if store.profiles.isEmpty {
                            Text("为 App 添加映射")
                                .font(.title3.weight(.semibold))
                            Text("为你选择的 App 单独设置触控板区域")
                                .foregroundStyle(.secondary)
                            Button("添加 App…", action: store.addApplication)
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 3)
                        } else {
                            Text("选择一个应用配置")
                                .font(.title3.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 750, idealWidth: 820, minHeight: 520, idealHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "hand.tap")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("触控板映射")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Toggle("启用映射", isOn: $store.enabled)
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 21)
        .padding(.vertical, 15)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("应用配置")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 14)
                .padding(.top, 15)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.profiles) { profile in
                        profileRow(profile)
                    }
                }
                .padding(.horizontal, 7)
            }

            Divider()

            HStack {
                Button(action: store.addApplication) {
                    Label("添加 App…", systemImage: "plus")
                }
                .help("从 Finder 选择应用程序")

                Spacer()

                Button(action: store.removeSelectedProfile) {
                    Label("删除配置", systemImage: "minus")
                        .labelStyle(.iconOnly)
                }
                .disabled(store.selectedProfile == nil)
                .help("删除选中的应用配置")
            }
            .controlSize(.small)
            .padding(10)
        }
        .frame(width: 196)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func profileRow(_ profile: AppProfile) -> some View {
        let selected = store.selectedID == profile.id

        return HStack(spacing: 9) {
            Button {
                store.selectedID = profile.id
            } label: {
                HStack(spacing: 8) {
                    if let icon = profile.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "app")
                            .frame(width: 22, height: 22)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    Text(profile.name)
                        .fontWeight(selected ? .medium : .regular)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])

            Toggle("在 \(profile.name) 中启用映射", isOn: profileValue(profile, \.isEnabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("\(profile.name) 处于前台时启用映射")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }

    private func profileEditor(_ profile: AppProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                        Text(profile.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Picker("映射到", selection: profileValue(profile, \.target)) {
                        Text("App 窗口").tag(MappingTarget.window)
                        Text("显示器").tag(MappingTarget.display)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    Text("触控板区域")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("缩小区域后，手指移动更短的距离就能划过同样大的目标区域。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                RegionEditor(region: profileValue(profile, \.source),
                             label: "触控板区域", resetTitle: "全触控板")

                Divider()

                DisclosureGroup("调整目标区域") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("选择 App 窗口或显示器中用来接收映射的范围。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        RegionEditor(region: profileValue(profile, \.destination),
                                     label: "目标区域", resetTitle: "完整目标")
                    }
                    .padding(.top, 10)
                }
                .disclosureGroupStyle(FullWidthDisclosureStyle())

                if profile.id == AppProfile.osuID {
                    Text("在 osu!lazer 里关闭 High Precision Mouse（高精度鼠标）。用触控板瞄准，用键盘 Z / X 击打。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(store.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("映射状态")
                .accessibilityValue(store.status)

            if store.needsPermission {
                Button("授权辅助功能…", action: store.requestPermission)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 21)
        .padding(.vertical, 11)
    }

    private func profileValue<Value>(_ profile: AppProfile,
                                     _ path: WritableKeyPath<AppProfile, Value>) -> Binding<Value> {
        Binding {
            let current = store.profiles.first { $0.id == profile.id } ?? profile
            return current[keyPath: path]
        } set: { value in
            guard var current = store.profiles.first(where: { $0.id == profile.id }) else { return }
            current[keyPath: path] = value
            store.updateProfile(current)
        }
    }
}

private struct FullWidthDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    configuration.label
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "已展开" : "已折叠")

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

private struct RegionEditor: View {
    @Binding var region: NormalizedRegion
    let label: String
    let resetTitle: String

    var body: some View {
        let previewWidth: CGFloat = 220

        HStack(alignment: .center, spacing: 21) {
            VStack(alignment: .leading, spacing: 6) {
                RegionPreview(region: $region, label: label)
                    .frame(width: previewWidth, height: 140)

                HStack(spacing: 4) {
                    Text("拖边角缩放，拖框内移动")
                    Spacer(minLength: 4)
                    Text("左 \(region.x.formatted(.percent)) · 上 \(region.y.formatted(.percent))")
                        .monospacedDigit()
                        .accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: previewWidth)
            }

            VStack(alignment: .leading, spacing: 11) {
                sizeSlider("宽度", value: Binding {
                    region.width
                } set: { width in
                    region = region.resized(width: width, height: region.height)
                })

                sizeSlider("高度", value: Binding {
                    region.height
                } set: { height in
                    region = region.resized(width: region.width, height: height)
                })

                HStack(spacing: 9) {
                    Button("居中") {
                        region = region.moved(toX: (1 - region.width) / 2, y: (1 - region.height) / 2)
                    }

                    Button(resetTitle) { region = .full }
                }
                .controlSize(.small)
                .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sizeSlider(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 7) {
            Slider(value: value, in: NormalizedRegion.minimumSize...1) { Text(title) }
                .accessibilityValue(value.wrappedValue.formatted(.percent.precision(.fractionLength(0))))

            Text(value.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 39, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

private struct RegionPreview: View {
    @Binding var region: NormalizedRegion
    let label: String
    @State private var dragOrigin: NormalizedRegion?
    @GestureState private var isDragging = false

    private static let handles: [(horizontal: RegionResizeEdge?, vertical: RegionResizeEdge?)] = [
        (.minimum, .minimum), (nil, .minimum), (.maximum, .minimum),
        (.minimum, nil), (.maximum, nil),
        (.minimum, .maximum), (nil, .maximum), (.maximum, .maximum)
    ]

    var body: some View {
        GeometryReader { geometry in
            let surface = CGRect(origin: .zero, size: geometry.size).insetBy(dx: 20, dy: 20)
            let selection = region.projected(into: surface)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .frame(width: surface.width, height: surface.height)
                    .position(x: surface.midX, y: surface.midY)
                    .allowsHitTesting(false)

                Path { path in
                    path.move(to: CGPoint(x: surface.midX, y: surface.minY))
                    path.addLine(to: CGPoint(x: surface.midX, y: surface.maxY))
                    path.move(to: CGPoint(x: surface.minX, y: surface.midY))
                    path.addLine(to: CGPoint(x: surface.maxX, y: surface.midY))
                }
                .stroke(Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.19))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                    .frame(width: selection.width, height: selection.height)
                    .contentShape(Rectangle())
                    .gesture(drag(in: surface.size))
                    .position(x: selection.midX, y: selection.midY)

                ForEach(Self.handles.indices, id: \.self) { index in
                    let handle = Self.handles[index]
                    resizeHandle(horizontal: handle.horizontal, vertical: handle.vertical)
                        .gesture(drag(in: surface.size, horizontal: handle.horizontal, vertical: handle.vertical))
                        .position(
                            x: handlePosition(handle.horizontal, center: selection.midX, length: selection.width),
                            y: handlePosition(handle.vertical, center: selection.midY, length: selection.height)
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .coordinateSpace(name: "regionSurface")
        }
        .onChange(of: isDragging) { _, active in
            if !active { dragOrigin = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("左侧 \(region.x.formatted(.percent))，顶部 \(region.y.formatted(.percent))，宽度 \(region.width.formatted(.percent))，高度 \(region.height.formatted(.percent))")
    }

    private func resizeHandle(horizontal: RegionResizeEdge?, vertical: RegionResizeEdge?) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor, lineWidth: 1.5) }
            .frame(width: horizontal == nil ? 11 : 7, height: vertical == nil ? 11 : 7)
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
    }

    private func handlePosition(_ edge: RegionResizeEdge?, center: CGFloat, length: CGFloat) -> CGFloat {
        // Keep the grab areas separate even at the smallest selectable size.
        let offset = max(length / 2, 14)
        switch edge {
        case .minimum: return center - offset
        case .maximum: return center + offset
        case nil: return center
        }
    }

    private func drag(in size: CGSize, horizontal: RegionResizeEdge? = nil,
                      vertical: RegionResizeEdge? = nil) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("regionSurface"))
            .updating($isDragging) { _, active, _ in active = true }
            .onChanged { gesture in
                let start = dragOrigin ?? region
                if dragOrigin == nil { dragOrigin = start }
                let deltaX = gesture.translation.width / size.width
                let deltaY = gesture.translation.height / size.height

                if horizontal == nil && vertical == nil {
                    region = start.moved(toX: start.x + deltaX, y: start.y + deltaY)
                } else {
                    region = start.resizing(horizontal: horizontal, vertical: vertical, deltaX: deltaX, deltaY: deltaY)
                }
            }
            .onEnded { _ in dragOrigin = nil }
    }
}
