import json
import tempfile
import unittest
from pathlib import Path
from Training.common import check_rights,digest,validate_recipe
from Training.preprocessing.prepare_sft import prepare

class PipelineTests(unittest.TestCase):
    def test_photo_authorization_is_bound_to_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);photo=root/"test.jpg";photo.write_bytes(b"synthetic authorization fixture, not a photograph")
            row={"sample_id":"test","image":"test.jpg","instruction":"提亮","rights":{"training_allowed":True,"license":"unit-test","source":"test fixture","sha256":digest(photo)}}
            self.assertEqual(check_rights(row,root),photo.resolve())
            photo.write_bytes(b"different bytes")
            with self.assertRaises(ValueError):check_rights(row,root)
            row["rights"]["training_allowed"]=False
            with self.assertRaises(ValueError):check_rights(row,root)

    def test_recipe_schema_rejects_executable_content(self):
        recipe={"version":1,"global":{},"color":{},"beauty":{},"masks":[],"operations":[],"evaluation":{}}
        validate_recipe(recipe)
        validate_recipe({"version":2,"global":{"exposure":0.3,"texture":0.2}})
        with self.assertRaises(Exception):validate_recipe({"version":3})
        recipe["shell"]="malicious command"
        with self.assertRaises(Exception):validate_recipe(recipe)

    def test_baseline_cannot_silently_become_sft_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);data=root/"input.jsonl"
            data.write_text(json.dumps({"accepted":True,"eligible_for_student_training":False})+"\n")
            with self.assertRaises(ValueError):prepare(data,root/"sft")

    def test_dataset_split_keeps_original_images_disjoint(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);image=root/"render.jpg";image.write_bytes(b"render fixture only")
            recipe={"version":1,"global":{},"color":{},"beauty":{},"masks":[],"operations":[],"evaluation":{}}
            rows=[]
            for group in ["image-a","image-b","image-c"]:
                for variation in range(2):
                    rows.append({"sample_id":f"{group}-{variation}","accepted":True,"eligible_for_student_training":True,"rights":{"training_allowed":True,"sha256":group},"rendered_result":str(image),"rendered_sha256":digest(image),"student_prompt":"unit test prompt","teacher_recipe":recipe,"teacher":"test"})
            data=root/"data.jsonl";data.write_text("".join(json.dumps(r)+"\n" for r in rows));prepare(data,root/"out")
            train={json.loads(l)["image_sha256"] for l in (root/"out/train.jsonl").read_text().splitlines()}
            val={json.loads(l)["image_sha256"] for l in (root/"out/validation.jsonl").read_text().splitlines()}
            self.assertTrue(train and val);self.assertFalse(train&val)

    def test_distillation_losses_have_real_gradients(self):
        import torch
        from Training.distillation.losses import masked_logit_distillation,FeatureProjection
        torch.manual_seed(7)
        student=torch.randn(2,5,13,requires_grad=True);teacher=torch.randn(2,5,13)
        labels=torch.tensor([[-100,-100,2,3,4],[-100,-100,5,6,7]])
        loss=masked_logit_distillation(student,teacher,labels);loss.backward()
        self.assertTrue(torch.isfinite(loss));self.assertGreater(student.grad.abs().sum().item(),0)
        projection=FeatureProjection(4,7);features=torch.randn(2,5,4,requires_grad=True)
        feature_loss=projection(features,torch.randn(2,5,7),labels);feature_loss.backward()
        self.assertGreater(projection.projection.weight.grad.abs().sum().item(),0)
        with self.assertRaises(ValueError):masked_logit_distillation(student,torch.randn(2,5,14),labels)

    def test_specialist_network_trains_one_synthetic_step(self):
        import torch
        from Training.vision.models import SegmentationUNet
        # A small synthetic gradient check, explicitly not a trained or evaluated vision model.
        torch.manual_seed(7);model=SegmentationUNet(channels=1,base=8);optimizer=torch.optim.AdamW(model.parameters(),lr=.001)
        original=model.output.weight.detach().clone()
        loss=torch.nn.functional.binary_cross_entropy_with_logits(model(torch.rand(1,3,32,32)),torch.rand(1,1,32,32))
        loss.backward();optimizer.step()
        self.assertTrue(torch.isfinite(loss));self.assertFalse(torch.equal(original,model.output.weight.detach()))

if __name__=="__main__":unittest.main()
