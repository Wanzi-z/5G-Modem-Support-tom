class Cbi_base{
    root_element = null
    
    childNodeid = []


    create_root_element(root_element_props){
        this.root_element = this.createElement(root_element_props)
    }

    createElement(element_props){
        let new_element = document.createElement(element_props['label']);
        let ele_class = element_props['class'];
        typeof(ele_class) == 'undefined' ? ele_class = [] : ele_class;
        typeof(ele_class) == 'string' ? ele_class = [ele_class] : ele_class;
        for (let cls of ele_class)
        {
            new_element.classList.add(cls);
        }
        if (element_props['text'])
        {
            new_element.innerHTML = element_props['text'];
        }    
        //remove text class in element_props
        delete element_props['text'];
        delete element_props['label'];
        delete element_props['class'];
        new_element.id = typeof(ele_class[0]) == 'string' ? ele_class[0] + Math.random().toString(36).substring(3) : Math.random().toString(36).substring(3)
        for (let prop in element_props)
        {
            new_element.setAttribute(prop, element_props[prop])
        }
        if (this.root_element){this.appendElement(new_element)}
        return new_element
    }

    appendElement(ele)
    {
        let id = ele.id ? ele.id : Math.random().toString(36).substring(3)
        ele.id = id
        this.childNodeid.push(id)
        this.root_element.appendChild(ele)

    }

    removeElement(ele)
    {
        if (typeof ele == 'string' && this.childNodeid.includes(ele))
        {
            ele = document.getElementById(ele)
        }
        if (ele.id && this.childNodeid.includes(ele.id)) {
            this.root_element.removeChild(ele)
        }
        else
        {
            console.log("Element not found")
        }
    }

    init_element()
    {
        this.create_root_element({
            'label': this.cbi_element_label,
            'class': this.cbi_class
        })
        if (this.title_lable){
            this.title_element = this.createElement(
                {
                    "label": this.title_lable,
                    "display": "none",
                }
            )
        }
        if (this.descrption_class)
        {
            this.descrption_element = this.createElement(
                {
                    "label": "div",
                    "display": "none",
                    "class": [this.descrption_class]
                }
                )
        }
    }

    set title(title)
    {
        if (title) 
        {
            this.title_element.innerHTML = title
            this.title_element.setAttribute("display", "block")
        }
        else
        {
            this.title_element.setAttribute("display", "none")
        }
    }

    set descrption(descrption)
    {
        if (descrption) 
        {
            this.descrption_element.innerHTML = descrption
            this.descrption_element.setAttribute("display", "block")
        }
        else
        {
            this.descrption_element.setAttribute("display", "none")
        }
    
    }

    set ele_class(ele_class)
    {
        if (ele_class)
        {
            typeof(ele_class) == 'string' ? ele_class = [ele_class] : ele_class;
            for (let cls of ele_class)
            {
                new_element.classList.add(cls);
            }
        }
        else
        {
            new_element.setAttribute("class", "")
        }
    }

}

class Cbi_map extends Cbi_base {

    user_class = []
    cbiproprety = {}
    cbi_class = ["cbi-map"]
    descrption_class = ["cbi-map-descrption"]
    cbi_element_label = "div"
    title_lable = "h2"

    constructor(){
        super()
        this.init_element()
        this.root_element.i = this
        return this.root_element
    }

    
}

class Cbi_section extends Cbi_base {
    user_class = []
    cbiproprety = {}
    cbi_class = ["cbi-section"]
    descrption_class = ["cbi-section-descrption"]
    cbi_element_label = "fieldset"
    title_lable = "h3"
    constructor(){
        super()
        this.init_element()
        this.root_element.i = this
        return this.root_element
    }
}


class Cbi_table extends Cbi_base {
    static cbi_class = ["cbi-section-table"]
    static cbi_element_label = "div"
    constructor(){
        super()
        this.init_element()
       
        this.root_element.i = this
        return this.root_element
    }

    set headers(headers){
        if (headers.length > 0)
        {
            this.header = new Cbi_row()
            this.header.i.ele_class = "cbi-section-table-titles"
            for (let header of headers)
            {
                
            }
        }
    }

}

class Cbi_row extends Cbi_base {
    static cbi_class = ["tr"]
    static cbi_element_label = "div"
    constructor(){
        super()
        this.init_element()
    }

}

class Cbi_table_cell extends Cbi_base {
    static cbi_class = ["td"]
    static cbi_element_label = "div"
    constructor(){
        super()
        this.init_element()
    }
}

class Cbi_table_header extends Cbi_base {
    static cbi_class = ["td"]
    static cbi_element_label = "div"
    constructor(){
        super()
        this.init_element()
    }
}
