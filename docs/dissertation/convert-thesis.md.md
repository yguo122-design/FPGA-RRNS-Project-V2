# 论文转换工具

```dataviewjs
// 创建转换按钮
const button = dv.el('button', '开始转换', {
    style: 'padding: 10px 20px; background: #4CAF50; color: white; border: none; border-radius: 5px; cursor: pointer;'
});

button.onclick = async () => {
    const output = await dv.io.system("pandoc thesis.md -o thesis_final.tex --template=template.tex --standalone --toc --number-sections --listings --mathjax");
    dv.el('div', `转换结果: ${output}`, {style: 'margin-top: 10px; padding: 10px; background: #f0f0f0; border-radius: 5px;'});
}
```

点击上面的按钮开始转换。