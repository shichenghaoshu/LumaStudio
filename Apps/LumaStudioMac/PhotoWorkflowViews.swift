import SwiftUI
import PhotoCore

struct PhotoReviewActions: View {
    @ObservedObject var model: AppModel
    let ids: Set<UUID>
    var body: some View {
        Section("星标") {
            ForEach(0...5,id: \.self) { value in
                Button(value == 0 ? "清除星标" : String(repeating:"★",count:value)) {model.updateReview(for:ids,rating:value)}
                    .accessibilityLabel("设为 \(value) 星")
            }
        }
        Section("旗标") {
            ForEach(PhotoFlag.allCases) { flag in
                Button {model.updateReview(for:ids,flag:flag)} label: {Label(flag.title,systemImage:flag.symbol)}
            }
        }
    }
}

struct PhotoReviewMenu: View {
    @ObservedObject var model: AppModel
    let ids: Set<UUID>
    var title="标记"
    var body: some View {
        Menu {PhotoReviewActions(model:model,ids:ids)} label: {Label(title,systemImage:"star")}
            .disabled(ids.isEmpty || model.reviewBusy || model.workflowBusy)
            .accessibilityLabel(title)
    }
}

struct PhotoReviewBadge: View {
    let review: PhotoReview
    var body: some View {
        HStack(spacing:4) {
            if review.flag != .none {Image(systemName:review.flag.symbol)}
            if review.rating>0 {Text("\(review.rating)★").monospacedDigit()}
        }.font(.system(size:9,weight:.semibold)).foregroundStyle(review.flag == .rejected ? .white : studioAccent)
            .padding(.horizontal,4).padding(.vertical,3)
            .background(.black.opacity(review.rating>0 || review.flag != .none ? 0.75 : 0),in:RoundedRectangle(cornerRadius:3))
            .accessibilityLabel("\(review.flag.title)，\(review.rating) 星")
    }
}

struct PhotoFilterMenu: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Menu {
            Toggle("仅 RAW",isOn:$model.photoFilter.rawOnly)
            Picker("星标下限",selection:$model.photoFilter.minimumRating) {
                Text("不限星标").tag(0)
                ForEach(1...5,id: \.self) {Text("\($0) 星及以上").tag($0)}
            }
            Picker("旗标",selection:$model.photoFilter.flag) {ForEach(PhotoFlagFilter.allCases){Text($0.title).tag($0)}}
            Picker("排序",selection:$model.photoFilter.sort) {ForEach(PhotoSortOrder.allCases){Text($0.title).tag($0)}}
            Divider()
            Button("清除所有筛选"){model.photoFilter=PhotoFilter()}.disabled(!model.photoFilter.isActive)
        } label: {Label(model.photoFilter.isActive ? "已筛选" : "筛选",systemImage:model.photoFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")}
            .accessibilityLabel("照片筛选与排序")
    }
}

struct PhotoWorkflowToolbar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:14) {
                Text("显示 \(model.visibleAssets.count) / \(model.assets.count) 张").font(.caption).foregroundStyle(.secondary)
                TextField("查找照片",text:$model.photoFilter.query).textFieldStyle(.roundedBorder).frame(maxWidth:220).accessibilityLabel("批量查找照片")
                PhotoFilterMenu(model:model)
                PhotoReviewMenu(model:model,ids:model.selection,title:"标记所选")
                Spacer(minLength:8)
                Button("同步所选参数…"){model.recipeSyncPresented=true}.disabled(!model.canSynchronize)
                if model.lastRecipeSync != nil {
                    Button("撤回上次同步"){model.undoRecipeSynchronization()}.disabled(model.workflowBusy || model.agentBusy || model.batchSnapshot?.active == true)
                }
            }.controlSize(.small)
            if !model.workflowStatus.isEmpty {Text(model.workflowStatus).font(.caption).foregroundStyle(studioAccent)}
        }.padding(.horizontal,24).padding(.vertical,12)
    }
}

struct RecipeSyncSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let source: PhotoAsset?
    let sourceRecipe: Recipe
    @State private var targets: Set<UUID>
    @State private var groups = RecipeSyncGroup.recommended
    @State private var applying = false
    @State private var failure: String?
    init(model: AppModel) {
        self.model=model;source=model.selected;sourceRecipe=model.recipe
        _targets=State(initialValue:model.selection.subtracting(Set([model.selectedID].compactMap{$0})).intersection(Set(model.visibleAssets.map(\.id))))
    }
    private var candidates: [PhotoAsset] {model.visibleAssets.filter{$0.id != source?.id}}
    private var validTargets: Set<UUID> {targets.intersection(Set(candidates.map(\.id)))}
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            VStack(alignment:.leading,spacing:6) {
                Text("同步照片参数").font(.title2.weight(.semibold))
                Text("来源：\(source?.name ?? "未选择照片")").font(.callout).lineLimit(1)
                Text("选择要复制的分组与目标照片。保留目标照片已锁定的参数。").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack(alignment:.top,spacing:22) {
                VStack(alignment:.leading,spacing:10) {
                    HStack {
                        Text("参数分组 · \(groups.count)").font(.headline)
                        Spacer()
                        Button("推荐"){groups=RecipeSyncGroup.recommended}
                        Button("清空"){groups=[]}
                    }.font(.caption)
                    ScrollView {
                        VStack(alignment:.leading,spacing:14) {
                            ForEach(RecipeSyncGroup.allCases) { group in
                                Toggle(isOn:Binding(get:{groups.contains(group)},set:{if $0{groups.insert(group)}else{groups.remove(group)}})) {
                                    VStack(alignment:.leading,spacing:3) {
                                        Text(group.title).font(.callout)
                                        Text(group.note).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                                    }
                                }.toggleStyle(.checkbox).disabled(group == .raw && source?.isRAW != true)
                                    .accessibilityLabel("同步"+group.title)
                            }
                        }.padding(.trailing,6).padding(.vertical,4)
                    }
                }.frame(width:305)
                Divider()
                VStack(alignment:.leading,spacing:10) {
                    HStack {
                        Text("目标 · \(validTargets.count) / \(candidates.count)").font(.headline)
                        Spacer()
                        Button("全选可见"){targets=Set(candidates.map(\.id))}
                        Button("清空"){targets=[]}
                    }.font(.caption)
                    if candidates.isEmpty {
                        ContentUnavailableView("没有可选照片",systemImage:"photo.on.rectangle",description:Text("请导入更多照片，或清除图库筛选。"))
                    } else {
                        ScrollView {
                            LazyVStack(alignment:.leading,spacing:10) {
                                ForEach(candidates) {asset in
                                    Toggle(isOn:Binding(get:{targets.contains(asset.id)},set:{if $0{targets.insert(asset.id)}else{targets.remove(asset.id)}})) {
                                        HStack(spacing:8) {
                                            AsyncImage(url:asset.thumbnailURL){$0.resizable().scaledToFit()}placeholder:{Color(white:0.12)}.frame(width:44,height:35)
                                            VStack(alignment:.leading,spacing:3) {
                                                Text(asset.name).font(.caption).lineLimit(1)
                                                PhotoReviewBadge(review:model.review(for:asset.id))
                                            }
                                        }
                                    }.toggleStyle(.checkbox).accessibilityLabel("同步目标 "+asset.name)
                                }
                            }.padding(.vertical,4)
                        }
                    }
                }.frame(maxWidth:.infinity)
            }
            if groups.contains(.geometry) || groups.contains(.masks) {
                Text("已选择覆盖构图或局部区域；画笔位置不会自动追踪不同照片的主体。").font(.caption).foregroundStyle(.orange)
            }
            if let failure {Text(failure).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)}
            Divider()
            HStack {
                Text("同步只保存编辑参数；可在本次打开期间撤回。").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("取消"){dismiss()}.keyboardShortcut(.cancelAction)
                Button(applying ? "正在同步…" : "同步到 \(validTargets.count) 张") {
                    guard let source else {return};applying=true;failure=nil
                    Task {do {
                        try await model.synchronizeRecipe(sourceRecipe,from:source.id,to:validTargets,groups:groups)
                        dismiss()
                    } catch {failure=error.localizedDescription;applying=false}}
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(validTargets.isEmpty || groups.isEmpty || !model.canSynchronize)
            }
        }.padding(24).frame(width:748,height:610).disabled(applying).interactiveDismissDisabled(applying)
    }
}
