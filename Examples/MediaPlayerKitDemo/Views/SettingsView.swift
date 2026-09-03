import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct SettingsView: View {
    @ObservedObject private var apiService = StreamAPIService.shared
    
    @State private var newDomainInput: String = ""
    @State private var newRemarkInput: String = ""
    @State private var showAddAlert: Bool = false
    @State private var toastMessage: String? = nil
    
    public init() {}

    public var body: some View {
        Form {
            // MARK: - 1. 当前生效节点选择 (下拉列表)
            Section(header: Label("当前工作节点", systemImage: "antenna.radiowaves.left.and.right")) {
                if apiService.nodeItems.isEmpty {
                    Text("暂无节点，请在下方添加新节点")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Picker("生效节点", selection: $apiService.activeNodeDomain) {
                        ForEach(apiService.nodeItems) { item in
                            Text(item.displayText).tag(item.domain)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    HStack {
                        Text("当前生效域名:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(apiService.activeNodeDomain.isEmpty ? "未选择" : apiService.activeNodeDomain)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }
            }
            
            // MARK: - 2. 基础调度参数配置
            Section(header: Label("基础调度参数", systemImage: "gearshape.fill")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("接口域名 (API Domain):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("例如 vadmin.weizan.cn", text: $apiService.apiDomain)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 13))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sign 鉴权参数:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("例如 !@#$VZanLIVE", text: $apiService.sign)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 13))
                }
            }
            
            // MARK: - 3. 新增节点录入
            Section(header: Label("添加新节点域名", systemImage: "plus.circle.fill")) {
                VStack(spacing: 8) {
                    TextField("节点域名 (如 p1.vzan.com:8000)", text: $newDomainInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 13))
                    
                    TextField("节点备注 (如 广州测试节点)", text: $newRemarkInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 13))
                    
                    Button(action: {
                        addNewNode()
                    }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("添加并保存节点")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(newDomainInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .disabled(newDomainInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            // MARK: - 4. 已录入节点库列表
            Section(header: HStack {
                Label("已保存节点列表 (\(apiService.nodeItems.count))", systemImage: "list.bullet")
                Spacer()
                Text("左滑可删除").font(.caption2).foregroundColor(.secondary)
            }) {
                if apiService.nodeItems.isEmpty {
                    Text("暂无已保存的节点")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(apiService.nodeItems) { item in
                        Button(action: {
                            apiService.setActiveNode(domain: item.domain)
                            showToast("已切换到节点: \(item.displayText)")
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        if !item.remark.isEmpty {
                                            Text(item.remark)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.primary)
                                        }
                                        if apiService.activeNodeDomain == item.domain {
                                            Text("生效中")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.green)
                                                .foregroundColor(.white)
                                                .cornerRadius(4)
                                        }
                                    }
                                    Text(item.domain)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if apiService.activeNodeDomain == item.domain {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .onDelete(perform: apiService.deleteNode)
                }
            }
            
            // MARK: - 5. 调试与缓存操作
            Section(header: Label("缓存与状态", systemImage: "wrench.and.screwdriver")) {
                Button(action: {
                    apiService.fetchStreamList()
                    showToast("已触发节点流列表刷新")
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("立即拉取当前节点流列表")
                    }
                }
                
                Button(action: {
                    apiService.sourcesCache.removeAll()
                    showToast("播放源缓存已清空")
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("清空播放源内存缓存")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("系统与节点配置")
        .overlay(
            Group {
                if let msg = toastMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .padding(.bottom, 20)
                    }
                    .transition(.opacity)
                    .animation(.easeInOut, value: toastMessage)
                }
            }
        )
    }
    
    private func addNewNode() {
        let domain = newDomainInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let remark = newRemarkInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty else { return }
        
        apiService.addNode(domain: domain, remark: remark)
        newDomainInput = ""
        newRemarkInput = ""
        showToast("节点已成功保存！")
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            toastMessage = nil
        }
    }
}
