#include <metal_stdlib>
using namespace metal;

struct VertexInput {
    float4 position [[attribute(0)]];
    float2 texCoords [[attribute(1)]];
};

struct VertexOutput {
    float4 position [[position]];
    float2 texCoords;
};

// 顶点着色器
vertex VertexOutput playerVertexShader(uint vertexID [[vertex_id]]) {
    // 渲染全屏四边形
    const float4 positions[4] = {
        float4(-1.0, -1.0, 0.0, 1.0),
        float4( 1.0, -1.0, 0.0, 1.0),
        float4(-1.0,  1.0, 0.0, 1.0),
        float4( 1.0,  1.0, 0.0, 1.0)
    };
    
    const float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    
    VertexOutput out;
    out.position = positions[vertexID];
    out.texCoords = texCoords[vertexID];
    return out;
}

// 片段着色器：NV12 (8-bit Y + UV) 转 BT.709 sRGB
fragment float4 nv12FragmentShaderBT709(VertexOutput in [[stage_in]],
                                       texture2d<float> yTexture [[texture(0)]],
                                       texture2d<float> uvTexture [[texture(1)]],
                                       sampler textureSampler [[sampler(0)]]) {
    float y = yTexture.sample(textureSampler, in.texCoords).r;
    float2 uv = uvTexture.sample(textureSampler, in.texCoords).rg - float2(0.5, 0.5);
    
    // BT.709 色彩空间转换矩阵
    float3 yuv = float3(y, uv);
    float3x3 colorMatrix = float3x3(
        float3(1.0,      1.0,       1.0),
        float3(0.0,     -0.187324,  1.8556),
        float3(1.5748,  -0.468124,  0.0)
    );
    
    float3 rgb = colorMatrix * yuv;
    return float4(clamp(rgb, 0.0, 1.0), 1.0);
}

// 片段着色器：BT.601 标清色域转换
fragment float4 nv12FragmentShaderBT601(VertexOutput in [[stage_in]],
                                       texture2d<float> yTexture [[texture(0)]],
                                       texture2d<float> uvTexture [[texture(1)]],
                                       sampler textureSampler [[sampler(0)]]) {
    float y = yTexture.sample(textureSampler, in.texCoords).r;
    float2 uv = uvTexture.sample(textureSampler, in.texCoords).rg - float2(0.5, 0.5);
    
    // BT.601 色彩空间转换矩阵
    float3 yuv = float3(y, uv);
    float3x3 colorMatrix = float3x3(
        float3(1.0,      1.0,       1.0),
        float3(0.0,     -0.344136,  1.7720),
        float3(1.4020,  -0.714136,  0.0)
    );
    
    float3 rgb = colorMatrix * yuv;
    return float4(clamp(rgb, 0.0, 1.0), 1.0);
}
