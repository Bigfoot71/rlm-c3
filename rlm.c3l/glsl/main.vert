<ATTR> vec2 POS;
<VARY> vec2 UV;

void main()
{
    UV = POS;

    gl_Position = vec4(POS * 2.0 - 1.0, 0.0, 1.0);
}
