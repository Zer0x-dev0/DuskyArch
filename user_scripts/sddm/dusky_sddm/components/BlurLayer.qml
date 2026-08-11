import QtQuick 2.15

// Full-screen vibrant gaussian blur overlay.
// Sits above the sharp wallpaper and below the translucent login card,
// giving the "blur-behind" look without requiring QtGraphicalEffects.

ShaderEffect {
    id: root

    property variant source: null
    property real blurRadius: 18.0
    property real saturation: 1.28
    property vector2d texelSize: Qt.vector2d(0.0, 0.0)

    fragmentShader: "
        varying highp vec2 qt_TexCoord0;
        uniform sampler2D source;
        uniform highp vec2 texelSize;
        uniform highp float blurRadius;
        uniform highp float saturation;
        uniform lowp float qt_Opacity;

        void main() {
            highp vec2 uv = qt_TexCoord0;
            highp vec4 col = vec4(0.0);
            highp float total = 0.0;

            for (int i = 0; i < 8; i++) {
                highp float off = float(i);
                highp vec2 dir = vec2(off * blurRadius * texelSize.x, off * blurRadius * texelSize.y);
                col += texture2D(source, uv + dir);
                col += texture2D(source, uv - dir);
                total += 2.0;
            }

            col /= total;

            // vibrant: boost saturation
            highp float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
            col.rgb = mix(vec3(luma), col.rgb, saturation);
            col.a = 1.0;

            gl_FragColor = col * qt_Opacity;
        }
    "
}
