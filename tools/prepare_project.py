"""Validate the portable TD project and refresh its include compatibility file."""
from pathlib import Path
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
def prepare():
    project=ROOT/'project/vehicle_media.al'
    tree=ET.parse(project);files=[]
    for entry in tree.findall('./Source_Files/Verilog/File'):
        path=(project.parent/entry.attrib['Path']).resolve()
        if not path.is_file():raise FileNotFoundError(path)
        files.append(path.relative_to(ROOT).as_posix())
    tree.getroot().set('Path',(ROOT/'project').as_posix())
    ET.indent(tree,space='  ');tree.write(project,encoding='utf-8',xml_declaration=True)
    compat=ROOT/'user_source/hdl_source/include/global_def.v'
    compat.parent.mkdir(parents=True,exist_ok=True)
    compat.write_bytes((ROOT/'vendor/include/global_def.v').read_bytes())
    return files
if __name__=='__main__':prepare()
